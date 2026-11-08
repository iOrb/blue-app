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
