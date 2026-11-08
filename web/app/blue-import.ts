import {
  type Library,
  type LocalText,
  type Value,
  text,
  uid,
  validLibrary,
} from "./blue-model.ts";
const normalize = (s: string) =>
  s
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .trim()
    .toLocaleLowerCase();
const matches = (a: LocalText, b: LocalText) =>
  ["en", "es"].some((l) => {
    const name = normalize(text(a, l as "en" | "es"));
    return (
      !!name &&
      ["en", "es"].some((r) => name === normalize(text(b, r as "en" | "es")))
    );
  });

/** Explicit, one-time migration. Existing browser values always win. */
export function importLibrary(
  current: Library,
  incoming: Library,
  importID: string,
): Library {
  if (
    !validLibrary(current) ||
    !validLibrary(incoming) ||
    !/^[\w-]{1,80}$/.test(importID)
  )
    throw new Error("invalid_import");
  if (current.imports?.includes(importID)) return current;
  const next = structuredClone(current);
  const usedIDs = new Set(
    [
      ...next.collections,
      ...next.records,
      ...next.notes,
      ...(next.events || []),
    ].map((x) => x.id),
  );
  const availableID = (id: string) => {
    const result = usedIDs.has(id) ? uid() : id;
    usedIDs.add(result);
    return result;
  };
  for (const source of incoming.collections) {
    let destination =
      next.collections.find((c) => c.id === source.id) ||
      next.collections.find((c) => matches(c.title, source.title));
    const fields = structuredClone(destination?.fields || []);
    const fieldMap = new Map<
      string,
      { id: string; options: Map<string, string> }
    >();
    for (const f of source.fields) {
      let existing = fields.find(
        (x) =>
          x.kind === f.kind && (x.id === f.id || matches(x.label, f.label)),
      );
      const options = new Map<string, string>();
      if (existing && f.kind === "status") {
        const merged = structuredClone(existing.options);
        for (const option of f.options) {
          const same = merged.find((o) => matches(o.label, option.label));
          let id = same?.id || option.id;
          if (!same) {
            while (merged.some((o) => o.id === id)) id += "_import";
            merged.push({ ...option, id });
          }
          options.set(option.id, id);
        }
        if (merged.length <= 12) existing.options = merged;
        else existing = undefined;
      }
      if (!existing) {
        let id = f.id;
        while (fields.some((x) => x.id === id)) id += "_import";
        existing = { ...structuredClone(f), id };
        fields.push(existing);
        options.clear();
      }
      fieldMap.set(f.id, { id: existing.id, options });
    }
    if (!destination || fields.length > 12) {
      destination = { ...structuredClone(source), id: availableID(source.id) };
      next.collections.push(destination);
      fieldMap.clear();
    } else destination.fields = fields;
    for (const item of incoming.records.filter(
      (r) => r.collectionID === source.id,
    )) {
      const values = Object.fromEntries(
        Object.entries(item.values).map(([id, value]) => {
          const mapped = fieldMap.get(id);
          const v: Value =
            value.option && mapped?.options.size
              ? { option: { _0: mapped.options.get(value.option._0)! } }
              : structuredClone(value);
          return [mapped?.id || id, v];
        }),
      );
      const existing = next.records.find(
        (r) =>
          r.collectionID === destination.id &&
          (r.id === item.id || normalize(r.title) === normalize(item.title)),
      );
      if (existing) {
        existing.values = { ...values, ...existing.values };
        if (!text(existing.markdown, "en") && !text(existing.markdown, "es"))
          existing.markdown = structuredClone(item.markdown);
        if (
          existing.favorite === undefined &&
          existing.values.favorite === undefined
        )
          existing.favorite = item.favorite;
        existing.sources = [
          ...(existing.sources || []),
          ...(item.sources || []).filter(
            (s) => !existing.sources?.some((x) => x.url === s.url),
          ),
        ].slice(0, 10);
      } else
        next.records.push({
          ...structuredClone(item),
          id: availableID(item.id),
          collectionID: destination.id,
          values,
        });
    }
  }
  for (const note of incoming.notes) {
    if (
      !next.notes.some(
        (n) =>
          n.id === note.id ||
          (matches(n.title, note.title) &&
            text(n.markdown, "en") === text(note.markdown, "en") &&
            text(n.markdown, "es") === text(note.markdown, "es")),
      )
    )
      next.notes.push({ ...structuredClone(note), id: availableID(note.id) });
  }
  for (const event of incoming.events || []) {
    if (!next.events?.some((e) => e.id === event.id))
      (next.events ||= []).push({
        ...structuredClone(event),
        id: availableID(event.id),
      });
  }
  next.imports = [...(next.imports || []), importID];
  if (!validLibrary(next)) throw new Error("invalid_merge");
  return next;
}
