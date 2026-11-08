import { type Library, type Language, text } from "./blue-model.ts";
export const dateKey = (date: Date) =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
export const dateFromKey = (key: string) => {
  const [year, month, day] = key.split("-").map(Number);
  return new Date(year, month - 1, day, 12);
};
export function monthDays(month: Date, language: Language) {
  const start = new Date(month.getFullYear(), month.getMonth(), 1, 12);
  const offset = (start.getDay() - (language === "es" ? 1 : 0) + 7) % 7;
  return Array.from(
    { length: 42 },
    (_, n) =>
      new Date(start.getFullYear(), start.getMonth(), 1 - offset + n, 12),
  );
}
export function agenda(library: Library, day: string, language: Language) {
  const events = (library.events || [])
    .filter(
      (e) =>
        (e.allDay ? e.day : dateKey(new Date((e.date + 978307200) * 1000))) ===
        day,
    )
    .map((e) => ({
      id: e.id,
      title: e.title,
      date: e.date,
      allDay: e.allDay,
      color: e.color,
      eventID: e.id,
      recordID: undefined as string | undefined,
      symbol: undefined as string | undefined,
      detail: "",
    }));
  for (const collection of library.collections) {
    for (const field of collection.fields.filter((f) => f.kind === "date")) {
      for (const record of library.records.filter(
        (r) => r.collectionID === collection.id,
      )) {
        const date = record.values[field.id]?.date?._0;
        if (
          date === undefined ||
          dateKey(new Date((date + 978307200) * 1000)) !== day
        )
          continue;
        events.push({
          id: `${record.id}:${field.id}`,
          title: record.title,
          date,
          allDay: true,
          color: "blue",
          eventID: "",
          recordID: record.id,
          symbol: collection.symbol,
          detail: text(field.label, language),
        });
      }
    }
  }
  return events.sort(
    (a, b) =>
      Number(b.allDay) - Number(a.allDay) ||
      a.date - b.date ||
      a.title.localeCompare(b.title),
  );
}
