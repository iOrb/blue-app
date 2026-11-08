import test from "node:test";
import assert from "node:assert/strict";
import {
  emptyLibrary,
  validLibrary,
  queryItems,
  userText,
  uid,
  now,
  safeLink,
  favorite,
  type Collection,
  type Item,
} from "./blue-model.ts";
const collection: Collection = {
  id: uid(),
  title: userText("Movies"),
  symbol: "🚬",
  fields: [
    {
      id: "bass",
      kind: "checkbox",
      label: userText("Bass"),
      icon: "🗿",
      tint: "purple",
      options: [],
      showInRow: true,
    },
    {
      id: "rating",
      kind: "rating",
      label: userText("Rating"),
      options: [],
      showInRow: true,
    },
    {
      id: "year",
      kind: "date",
      label: userText("Date"),
      options: [],
      showInRow: true,
    },
  ],
  createdAt: now(),
};
const record = (title: string, score?: number): Item => ({
  id: uid(),
  collectionID: collection.id,
  title,
  markdown: userText(""),
  values: score === undefined ? {} : { rating: { number: { _0: score } } },
  revision: 0,
  updatedAt: now(),
});
test("accepts the native Codable format and rejects invalid imports without throwing", () => {
  const s = {
    ...emptyLibrary(),
    collections: [collection],
    records: [record("Interstellar", 8.5)],
  };
  assert.equal(validLibrary(s), true);
  assert.equal(validLibrary({ ...s, folders: [{}] }), false);
  assert.equal(
    validLibrary({
      ...s,
      records: [
        { ...s.records[0], values: { rating: { number: { _0: 11 } } } },
      ],
    }),
    false,
  );
  assert.equal(
    validLibrary({
      ...s,
      records: [
        { ...s.records[0], values: { unknown: { flag: { _0: true } } } },
      ],
    }),
    false,
  );
  assert.equal(
    validLibrary({ ...s, records: [s.records[0], s.records[0]] }),
    false,
  );
  assert.equal(validLibrary(null), false);
  assert.equal(
    validLibrary({
      formatVersion: 2,
      collections: [null],
      records: [],
      notes: [],
      alarms: [],
      folders: [],
    }),
    false,
  );
});
test("filters indicators and favorites consistently and leaves missing values last", () => {
  const a = {
    ...record("Interstellar", 8.5),
    favorite: true,
    values: { rating: { number: { _0: 8.5 } }, bass: { flag: { _0: true } } },
  };
  const b = record("Arrival", 9);
  const c = record("Dune");
  const q = { sortField: "rating", ascending: false, filters: [] };
  assert.deepEqual(
    queryItems([a, b, c], q, "", "en").map((r) => r.title),
    ["Arrival", "Interstellar", "Dune"],
  );
  assert.deepEqual(
    queryItems(
      [a, b, c],
      {
        ...q,
        filters: [
          { fieldID: "__favorite", flag: true },
          { fieldID: "bass", flag: true },
        ],
      },
      "",
      "en",
    ).map((r) => r.title),
    ["Interstellar"],
  );
  assert.equal(favorite(a), true);
  assert.equal(
    queryItems(
      [a, b, c],
      { ...q, filters: [{ fieldID: "rating", minimum: 9 }] },
      "",
      "en",
    ).length,
    1,
  );
});
test("honors model date filters and allows only web links", () => {
  const a = { ...record("Old"), values: { year: { date: { _0: 50 } } } };
  const b = { ...record("New"), values: { year: { date: { _0: 150 } } } };
  assert.deepEqual(
    queryItems(
      [a, b],
      {
        sortField: "title",
        ascending: true,
        filters: [{ fieldID: "year", after: 100, before: 200 }],
      },
      "",
      "en",
    ).map((r) => r.title),
    ["New"],
  );
  assert.equal(safeLink("javascript:alert(1)"), undefined);
  assert.equal(
    safeLink("https://en.wikipedia.org/wiki/Interstellar_(film)"),
    "https://en.wikipedia.org/wiki/Interstellar_(film)",
  );
});

import { importLibrary } from "./blue-import.ts";
import { agenda, dateKey, monthDays } from "./blue-calendar-model.ts";
test("migration combines bilingual collections, preserves local values and custom icons, and runs only once", () => {
  const browser = {
    ...emptyLibrary(),
    collections: [collection],
    records: [record("Interstellar", 10)],
  };
  const importedCollection = {
    ...structuredClone(collection),
    id: uid(),
    title: { key: "template.movies", english: "", spanish: "" },
    symbol: "film",
  };
  const importedRecord = {
    ...record("Interstellar", 8),
    collectionID: importedCollection.id,
    values: { rating: { number: { _0: 8 } }, bass: { flag: { _0: true } } },
  };
  const incoming = {
    ...emptyLibrary(),
    collections: [importedCollection],
    records: [
      importedRecord,
      { ...record("Arrival", 9), collectionID: importedCollection.id },
    ],
  };
  const next = importLibrary(browser, incoming, "native-test");
  assert.equal(next.collections.length, 1);
  assert.equal(next.collections[0].symbol, "🚬");
  assert.equal(next.records.length, 2);
  assert.equal(next.records[0].values.rating?.number?._0, 10);
  assert.equal(next.records[0].values.bass?.flag?._0, true);
  assert.equal(browser.records[0].values.bass, undefined);
  next.records = [];
  assert.equal(importLibrary(next, incoming, "native-test"), next);
  assert.equal(
    next.records.length,
    0,
    "reloading must not restore deleted items",
  );
});
test("migration reconciles status option IDs without losing existing meanings", () => {
  const c = {
    ...structuredClone(collection),
    fields: [
      {
        id: "status",
        label: userText("Status"),
        kind: "status" as const,
        options: [{ id: "watched", label: userText("Watched") }],
        showInRow: true,
      },
    ],
  };
  const native = {
    ...structuredClone(c),
    id: uid(),
    fields: [
      {
        ...c.fields[0],
        options: [
          { id: "done", label: userText("Watched") },
          { id: "watched", label: userText("Planned") },
        ],
      },
    ],
  };
  const incoming = {
    ...emptyLibrary(),
    collections: [native],
    records: [
      {
        ...record("One"),
        collectionID: native.id,
        values: { status: { option: { _0: "done" } } },
      },
      {
        ...record("Two"),
        collectionID: native.id,
        values: { status: { option: { _0: "watched" } } },
      },
    ],
  };
  const result = importLibrary(
    { ...emptyLibrary(), collections: [c] },
    incoming,
    "native-status",
  );
  assert.equal(validLibrary(result), true);
  assert.equal(result.records[0].values.status.option?._0, "watched");
  assert.equal(result.records[1].values.status.option?._0, "watched_import");
});
test("calendar persists validated events and projects collection date fields", () => {
  const date = new Date(2026, 10, 8, 9, 30);
  const seconds = date.getTime() / 1000 - 978307200;
  const library = {
    ...emptyLibrary(),
    collections: [collection],
    records: [
      { ...record("Release"), values: { year: { date: { _0: seconds } } } },
    ],
    events: [
      {
        id: uid(),
        title: "Coffee",
        date: seconds,
        day: "2026-11-08",
        allDay: false,
        color: "blue",
        revision: 0,
      },
      {
        id: uid(),
        title: "Birthday",
        date: seconds,
        day: "2026-11-09",
        allDay: true,
        color: "purple",
        revision: 0,
      },
    ],
  };
  assert.equal(validLibrary(JSON.parse(JSON.stringify(library))), true);
  assert.deepEqual(
    agenda(library, "2026-11-08", "es").map((e) => e.title),
    ["Release", "Coffee"],
  );
  assert.deepEqual(
    agenda(library, "2026-11-09", "es").map((e) => e.title),
    ["Birthday"],
  );
  assert.equal(agenda(library, "2026-11-09", "es")[0].allDay, true);
  assert.equal(
    validLibrary({ ...library, events: [{ ...library.events[0], date: NaN }] }),
    false,
  );
  assert.equal(
    validLibrary({
      ...library,
      events: [{ ...library.events[1], day: "2026-02-31" }],
    }),
    false,
  );
  const days = monthDays(new Date(2026, 10, 1), "es");
  assert.equal(days.length, 42);
  assert.equal(days[0].getDay(), 1);
  assert.equal(dateKey(days.at(-1)!), "2026-12-06");
  assert.equal(new Set(days.map(dateKey)).size, 42);
});

test("validates shared indicator metadata and keeps only type-compatible values in schema changes", async () => {
  const { compatibleValue } = await import("./blue-model.ts");
  const numeric = {
    id: "score",
    label: userText("Score"),
    kind: "number" as const,
    options: [],
    showInRow: true,
    minimum: 1,
    maximum: 5,
    step: 1,
  };
  const library = {
    ...emptyLibrary(),
    collections: [{ ...collection, fields: [numeric] }],
  };
  assert.equal(validLibrary(library), true);
  assert.equal(compatibleValue(numeric, { number: { _0: 3 } }), true);
  assert.equal(compatibleValue(numeric, { number: { _0: 9 } }), false);
  assert.equal(
    compatibleValue({ ...numeric, kind: "text" }, { number: { _0: 3 } }),
    false,
  );
  assert.equal(
    validLibrary({
      ...library,
      collections: [{ ...collection, fields: [{ ...numeric, step: 0 }] }],
    }),
    false,
  );
  assert.equal(
    validLibrary({
      ...library,
      collections: [
        {
          ...collection,
          fields: [{ ...numeric, inactiveOptionID: "missing" }],
        },
      ],
    }),
    false,
  );
});

// Conversation transport is bounded independently from the saved library.
import { validHistory } from "./blue-conversation.ts";
test("conversation history rejects malformed or oversized messages", () => {
  assert.equal(validHistory([{ user: "hola", reply: "¡Hola!" }]), true);
  assert.equal(validHistory([{ user: "🗿".repeat(800), reply: "" }]), true);
  assert.equal(validHistory([{ user: "x".repeat(801), reply: "" }]), false);
  assert.equal(validHistory([{ user: "", reply: "x".repeat(1001) }]), false);
  assert.equal(validHistory(Array(5).fill({ user: "hola", reply: "hola" })), false);
  assert.equal(validHistory([{ user: {}, reply: "" }]), false);
  assert.equal(validHistory([null]), false);
});

test("unsaved note proposals carry bounded content and an exact revision", () => {
  const proposal = { noteID: uid(), revision: 2, markdown: "Shorter text." };
  assert.equal(validHistory([{ user: "Shorten this", reply: "Shorter text.", noteProposal: proposal }]), true);
  assert.equal(validHistory([{ user: "", reply: "", noteProposal: { ...proposal, revision: -1 } }]), false);
  assert.equal(validHistory([{ user: "", reply: "", noteProposal: { ...proposal, markdown: "x".repeat(20001) } }]), false);
  assert.equal(validHistory([{ user: "", reply: "", noteProposal: { ...proposal, noteID: "guess" } }]), false);
  assert.equal(validHistory([{ user: "👩‍👩‍👧‍👧".repeat(800), reply: "" }]), true);
});
