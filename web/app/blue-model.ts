import translations from "./native-strings.json" with { type: "json" };
export type Language = "en" | "es";
export type LocalText = { key?: string; english: string; spanish: string };
export type Kind =
  | "text"
  | "number"
  | "rating"
  | "date"
  | "status"
  | "checkbox"
  | "like"
  | "favorite"
  | "tags";
export type Value = {
  text?: { _0: string };
  number?: { _0: number };
  flag?: { _0: boolean };
  option?: { _0: string };
  tags?: { _0: string[] };
  date?: { _0: number };
};
export type Field = {
  id: string;
  label: LocalText;
  kind: Kind;
  options: { id: string; label: LocalText }[];
  showInRow: boolean;
  icon?: string;
  tint?: string;
};
export type Collection = {
  id: string;
  title: LocalText;
  symbol: string;
  fields: Field[];
  createdAt: number;
};
export type Item = {
  id: string;
  collectionID: string;
  title: string;
  markdown: LocalText;
  values: Record<string, Value>;
  favorite?: boolean;
  revision: number;
  updatedAt: number;
  sources?: { title: string; summary: string; url: string }[];
};
export type Note = {
  id: string;
  title: LocalText;
  markdown: LocalText;
  favorite?: boolean;
  revision: number;
  updatedAt: number;
};
export type Library = {
  formatVersion: 2;
  folders: never[];
  collections: Collection[];
  records: Item[];
  notes: Note[];
  alarms: never[];
};
export type Filter = {
  fieldID: string;
  text?: string;
  minimum?: number;
  maximum?: number;
  flag?: boolean;
  after?: number;
  before?: number;
};
export type Query = {
  sortField: string;
  ascending: boolean;
  filters: Filter[];
};
export const emptyLibrary = (): Library => ({
  formatVersion: 2,
  folders: [],
  collections: [],
  records: [],
  notes: [],
  alarms: [],
});
export const uid = () => crypto.randomUUID().toUpperCase();
export const now = () => Date.now() / 1000 - 978307200;
export const userText = (text: string): LocalText => ({
  english: text,
  spanish: text,
});
export const text = (value: LocalText, lang: Language) =>
  value?.[lang === "es" ? "spanish" : "english"] ||
  value?.english ||
  (value?.key
    ? (translations as Record<string, { en: string; es: string }>)[value.key]?.[
        lang
      ]
    : "") ||
  "";
export const boolean = (f: Field) =>
  ["checkbox", "favorite", "like"].includes(f.kind);
export const favorite = (r: Item) =>
  r.favorite ?? r.values.favorite?.flag?._0 ?? false;
export const favoriteField: Field = {
  id: "__favorite",
  label: { english: "Favorite", spanish: "Favorito" },
  kind: "favorite",
  options: [],
  showInRow: true,
  tint: "yellow",
};
export const colors = [
  "blue",
  "purple",
  "orange",
  "green",
  "red",
  "pink",
  "yellow",
];
export const value = (v: Value | undefined) =>
  v?.text?._0 ??
  v?.number?._0 ??
  v?.flag?._0 ??
  v?.option?._0 ??
  v?.tags?._0.join(", ") ??
  v?.date?._0 ??
  "";
export function displayValue(v: Value | undefined, f: Field, lang: Language) {
  const raw = value(v);
  if (f.kind === "status")
    return text(
      f.options.find((o) => o.id === raw)?.label || userText(String(raw)),
      lang,
    );
  if (f.kind === "date" && typeof raw === "number")
    return new Date((raw + 978307200) * 1000).toLocaleDateString(lang);
  if (typeof raw === "number")
    return new Intl.NumberFormat(lang, { maximumFractionDigits: 2 }).format(
      raw,
    );
  return String(raw);
}
export function queryItems(
  items: Item[],
  query: Query,
  search: string,
  lang: Language,
) {
  return items
    .filter(
      (r) =>
        (!search ||
          r.title.toLocaleLowerCase().includes(search.toLocaleLowerCase())) &&
        query.filters.every((f) => {
          const v =
            f.fieldID === "__favorite"
              ? favorite(r)
              : value(r.values[f.fieldID]);
          if (f.flag !== undefined && v !== f.flag) return false;
          if (f.after !== undefined && (typeof v !== "number" || v < f.after))
            return false;
          if (f.before !== undefined && (typeof v !== "number" || v > f.before))
            return false;
          if (
            f.minimum !== undefined &&
            (typeof v !== "number" || v < f.minimum)
          )
            return false;
          if (
            f.maximum !== undefined &&
            (typeof v !== "number" || v > f.maximum)
          )
            return false;
          return (
            !f.text ||
            String(v).toLocaleLowerCase().includes(f.text.toLocaleLowerCase())
          );
        }),
    )
    .sort((a, b) => {
      const x =
        query.sortField === "title"
          ? a.title
          : value(a.values[query.sortField]);
      const y =
        query.sortField === "title"
          ? b.title
          : value(b.values[query.sortField]);
      if (x === "" && y === "") return 0;
      if (x === "") return 1;
      if (y === "") return -1;
      const n =
        typeof x === "number" && typeof y === "number"
          ? x - y
          : String(x).localeCompare(String(y), lang, { numeric: true });
      return query.ascending ? n : -n;
    });
}
export function validLibrary(input: unknown): input is Library {
  try {
    if (!input || typeof input !== "object") return false;
    const s = input as Library;
    if (
      s.formatVersion !== 2 ||
      !Array.isArray(s.folders) ||
      s.folders.length ||
      !Array.isArray(s.collections) ||
      !Array.isArray(s.records) ||
      !Array.isArray(s.notes) ||
      !Array.isArray(s.alarms) ||
      s.alarms.length ||
      s.collections.length > 100 ||
      s.records.length > 10000 ||
      s.notes.length > 1000
    )
      return false;
    const validText = (t: LocalText, max: number) =>
      !!t &&
      typeof t.english === "string" &&
      typeof t.spanish === "string" &&
      t.english.length <= max &&
      t.spanish.length <= max;
    const ids = new Set<string>();
    const validID = (id: string) =>
      typeof id === "string" &&
      /^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$/.test(id) &&
      !ids.has(id.toUpperCase()) &&
      !!ids.add(id.toUpperCase());
    for (const c of s.collections) {
      if (
        !validID(c.id) ||
        !validText(c.title, 240) ||
        typeof c.symbol !== "string" ||
        c.symbol.length > 80 ||
        !Number.isFinite(c.createdAt) ||
        !Array.isArray(c.fields) ||
        c.fields.length > 12
      )
        return false;
      const fields = new Set<string>();
      for (const f of c.fields) {
        if (
          typeof f.id !== "string" ||
          f.id.length > 80 ||
          fields.has(f.id) ||
          !validText(f.label, 240) ||
          ![
            "text",
            "number",
            "rating",
            "date",
            "status",
            "checkbox",
            "like",
            "favorite",
            "tags",
          ].includes(f.kind) ||
          !Array.isArray(f.options) ||
          f.options.length > 12 ||
          typeof f.showInRow !== "boolean" ||
          (f.icon !== undefined &&
            (typeof f.icon !== "string" || f.icon.length > 80)) ||
          (f.tint !== undefined && !colors.includes(f.tint))
        )
          return false;
        fields.add(f.id);
        if (
          !f.options.every(
            (o) =>
              typeof o.id === "string" &&
              o.id.length <= 80 &&
              validText(o.label, 240),
          )
        )
          return false;
      }
    }
    for (const r of s.records) {
      const c = s.collections.find((c) => c.id === r.collectionID);
      if (
        !c ||
        !validID(r.id) ||
        typeof r.title !== "string" ||
        r.title.length > 240 ||
        !validText(r.markdown, 20000) ||
        !r.values ||
        typeof r.values !== "object" ||
        !Number.isInteger(r.revision) ||
        !Number.isFinite(r.updatedAt) ||
        (r.favorite !== undefined && typeof r.favorite !== "boolean")
      )
        return false;
      if (
        r.sources !== undefined &&
        (!Array.isArray(r.sources) ||
          r.sources.length > 10 ||
          !r.sources.every(
            (x) =>
              typeof x.title === "string" &&
              typeof x.summary === "string" &&
              typeof x.url === "string" &&
              !!safeLink(x.url),
          ))
      )
        return false;
      for (const [id, v] of Object.entries(r.values)) {
        const f = c.fields.find((f) => f.id === id);
        if (!f || !v || Object.keys(v).length !== 1) return false;
        if (
          ["number", "rating"].includes(f.kind) &&
          (!Number.isFinite(v.number?._0) ||
            (f.kind === "rating" && (v.number!._0 < 0 || v.number!._0 > 10)))
        )
          return false;
        if (boolean(f) && typeof v.flag?._0 !== "boolean") return false;
        if (
          f.kind === "status" &&
          !f.options.some((o) => o.id === v.option?._0)
        )
          return false;
        if (
          f.kind === "text" &&
          (typeof v.text?._0 !== "string" || v.text._0.length > 20000)
        )
          return false;
        if (f.kind === "date" && !Number.isFinite(v.date?._0)) return false;
        if (
          f.kind === "tags" &&
          (!Array.isArray(v.tags?._0) ||
            v.tags._0.length > 50 ||
            !v.tags._0.every((t) => typeof t === "string" && t.length <= 240))
        )
          return false;
      }
    }
    return s.notes.every(
      (n) =>
        validID(n.id) &&
        validText(n.title, 240) &&
        validText(n.markdown, 20000) &&
        Number.isInteger(n.revision) &&
        Number.isFinite(n.updatedAt) &&
        (n.favorite === undefined || typeof n.favorite === "boolean"),
    );
  } catch {
    return false;
  }
}
export function safeLink(url: string) {
  try {
    const u = new URL(url);
    return ["https:", "http:"].includes(u.protocol) ? u.href : undefined;
  } catch {
    return undefined;
  }
}
