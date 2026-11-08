"use client";
import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  Plus,
  FileText,
  List,
  CalendarDays,
  Settings2,
  Trash2,
  ArrowUp,
  Mic,
  MicOff,
  LoaderCircle,
  SlidersHorizontal,
  Download,
  ChevronRight,
} from "lucide-react";
import {
  type Library,
  type Language,
  type Collection,
  type Item,
  type Note,
  type Field,
  type Value,
  type Query,
  type CalendarEvent,
  emptyLibrary,
  uid,
  now,
  userText,
  text,
  boolean,
  favorite,
  favoriteField,
  queryItems,
  validLibrary,
  compatibleValue,
  safeLink,
} from "./blue-model";
import { BlueMark, Symbol } from "./blue-icons";
import {
  Sheet,
  Confirm,
  EditableText,
  MarkdownBody,
  FieldControl,
  words,
} from "./blue-ui";
import { BlueCalendar, EventEditor } from "./blue-calendar";
import { dateKey } from "./blue-calendar-model";
import { importLibrary } from "./blue-import";
import strings from "./native-strings.json";
const STORE = "blue.web.library.v2";
type Scope = "all" | "notes" | "collections" | "calendar";
type Detail = { kind: "note" | "item"; id: string };
type Result = {
  answer?: { _0: string };
  message?: { _0: string };
  records?: { _0: string[]; edited: boolean };
  notes?: { _0: string[] };
  collection?: { _0: string };
  collectionView?: { _0: string; _1: Query };
  events?: { _0: string[] };
  selection?: {
    _0: {
      records: string[];
      notes: string[];
      collections: string[];
      events: string[];
      fields: string[];
      answer: string;
    };
  };
  confirmDeletion?: { _0: { kind: string; id: string } };
  confirmCollectionChange?: {
    _0: { original: Collection; proposed: Collection };
  };
};
export default function Blue() {
  const [library, setLibrary] = useState<Library>(emptyLibrary),
    current = useRef(library),
    [ready, setReady] = useState(false),
    [language, setLanguage] = useState<Language>("en");
  const [scope, setScope] = useState<Scope>("all"),
    [collectionID, setCollectionID] = useState<string>(),
    [detail, setDetail] = useState<Detail>(),
    session = useRef<{ id: string; revision: number } | undefined>(undefined);
  const [settings, setSettings] = useState(false),
    [search, setSearch] = useState(""),
    [filters, setFilters] = useState(false),
    [query, setQuery] = useState<Query>({
      sortField: "title",
      ascending: true,
      filters: [],
    });
  const [creating, setCreating] = useState(false),
    [newCollection, setNewCollection] = useState<string>(),
    [eventEditor, setEventEditor] = useState<{
      event?: CalendarEvent;
      day: string;
    }>(),
    [selectedDay, setSelectedDay] = useState(() => dateKey(new Date()));
  const [notice, setNotice] = useState(""),
    [deletion, setDeletion] = useState<{
      title: string;
      perform: () => void;
    }>();
  const [chat, setChat] = useState(false),
    [prompt, setPrompt] = useState(""),
    [busy, setBusy] = useState(false),
    [result, setResult] = useState<Result>(),
    [chatError, setChatError] = useState(""),
    [resultSnapshot, setResultSnapshot] = useState("");
  const [listening, setListening] = useState(false),
    recognition = useRef<any>(null),
    input = useRef<HTMLTextAreaElement>(null),
    canRead = useRef(true),
    conversationTarget = useRef<{
      record?: string;
      note?: string;
      collection?: string;
      event?: string;
    }>({});
  const t = (en: string, es: string) => words(language, en, es);
  useEffect(() => {
    try {
      const raw = localStorage.getItem(STORE);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (!validLibrary(parsed)) throw new Error();
        current.current = parsed;
        setLibrary(parsed);
      }
      const lang = localStorage.getItem("blue.web.language");
      if (lang === "en" || lang === "es") setLanguage(lang);
      setPrompt(localStorage.getItem("blue.web.prompt") || "");
    } catch {
      canRead.current = false;
      setNotice(
        "No se pudo abrir la biblioteca. / Could not open the saved library.",
      );
    }
    setReady(true);
    return () => recognition.current?.stop();
  }, []);
  useEffect(() => {
    if (!ready) return;
    document.documentElement.lang = language;
    try {
      localStorage.setItem("blue.web.language", language);
      localStorage.setItem("blue.web.prompt", prompt);
    } catch {}
  }, [language, prompt, ready]);
  useEffect(() => {
    if (!ready || !canRead.current) return;
    const abort = new AbortController();
    fetch("/api/library-import", { method: "POST", signal: abort.signal })
      .then(async (r) => {
        if (!r.ok) throw new Error();
        return r.json() as Promise<{ library: Library; importID: string }>;
      })
      .then((data) => {
        if (abort.signal.aborted) return;
        const next = importLibrary(
          current.current,
          data.library,
          data.importID,
        );
        if (next !== current.current) {
          localStorage.setItem(STORE, JSON.stringify(next));
          current.current = next;
          setLibrary(next);
        }
      })
      .catch(() => {
        if (!abort.signal.aborted)
          setNotice(
            t(
              "Could not load your lists. Reload to retry.",
              "No se pudieron cargar tus listas. Recarga para reintentar.",
            ),
          );
      });
    return () => abort.abort();
  }, [ready]);
  useEffect(() => {
    const receive = (e: StorageEvent) => {
      if (e.key !== STORE || !e.newValue) return;
      try {
        const next = JSON.parse(e.newValue);
        if (validLibrary(next)) {
          current.current = next;
          setLibrary(next);
        }
      } catch {}
    };
    window.addEventListener("storage", receive);
    return () => window.removeEventListener("storage", receive);
  }, []);
  const commit = (next: Library) => {
    if (!validLibrary(next)) {
      setNotice(
        t("Could not save that change.", "No se pudo guardar ese cambio."),
      );
      return false;
    }
    try {
      localStorage.setItem(STORE, JSON.stringify(next));
      current.current = next;
      setLibrary(next);
      return true;
    } catch {
      setNotice(
        t(
          "Storage unavailable. Keep this page open and export your library.",
          "Almacenamiento no disponible. Mantén abierta la página y exporta la biblioteca.",
        ),
      );
      return false;
    }
  };
  const navigate = (next: Scope) => {
    conversationTarget.current = {};
    setScope(next);
    setSettings(false);
    setCreating(false);
    setNewCollection(undefined);
    setEventEditor(undefined);
    setDeletion(undefined);
    setCollectionID(undefined);
    setDetail(undefined);
    setSearch("");
    setFilters(false);
    setChat(false);
    setQuery({ sortField: "title", ascending: true, filters: [] });
  };
  const openCollection = (id: string) => {
    conversationTarget.current = {};
    setCollectionID(id);
    setScope("collections");
    setDetail(undefined);
    setChat(false);
    setQuery({ sortField: "title", ascending: true, filters: [] });
    setSearch("");
  };
  const openDetail = (kind: "note" | "item", id: string) => {
    conversationTarget.current = {};
    const entity =
      kind === "item"
        ? current.current.records.find((r) => r.id === id)
        : current.current.notes.find((n) => n.id === id);
    if (!entity) return;
    session.current = { id, revision: entity.revision };
    setDetail({ kind, id });
    setChat(false);
  };
  const collection = library.collections.find((c) => c.id === collectionID),
    item =
      detail?.kind === "item"
        ? library.records.find((r) => r.id === detail.id)
        : undefined,
    note =
      detail?.kind === "note"
        ? library.notes.find((n) => n.id === detail.id)
        : undefined;
  const changeItem = (r: Item, patch: Partial<Item>) => {
    const old = current.current.records.find((x) => x.id === r.id);
    const expected =
      session.current?.id === r.id ? session.current.revision : r.revision;
    if (!old || old.revision !== expected) {
      setNotice(
        t(
          "This item changed. Reopen it before editing.",
          "Este elemento ha cambiado. Ábrelo de nuevo antes de editar.",
        ),
      );
      return;
    }
    const next = {
      ...old,
      ...patch,
      revision: old.revision + 1,
      updatedAt: now(),
    };
    if (
      commit({
        ...current.current,
        records: current.current.records.map((x) => (x.id === r.id ? next : x)),
      }) &&
      session.current?.id === r.id
    )
      session.current.revision = next.revision;
  };
  const changeValue = (r: Item, f: Field, v?: Value) => {
    if (f.id === "__favorite") {
      changeItem(r, { favorite: !!v?.flag?._0 });
      return;
    }
    const values = {
      ...(current.current.records.find((x) => x.id === r.id)?.values ||
        r.values),
    };
    if (v) values[f.id] = v;
    else delete values[f.id];
    changeItem(r, { values });
  };
  const changeNote = (n: Note, patch: Partial<Note>) => {
    const old = current.current.notes.find((x) => x.id === n.id);
    const expected =
      session.current?.id === n.id ? session.current.revision : n.revision;
    if (!old || old.revision !== expected) {
      setNotice(
        t(
          "This note changed. Reopen it before editing.",
          "Esta nota ha cambiado. Ábrela de nuevo antes de editar.",
        ),
      );
      return;
    }
    const next = {
      ...old,
      ...patch,
      revision: old.revision + 1,
      updatedAt: now(),
    };
    if (
      commit({
        ...current.current,
        notes: current.current.notes.map((x) => (x.id === n.id ? next : x)),
      }) &&
      session.current?.id === n.id
    )
      session.current.revision = next.revision;
  };
  const changeCollection = (c: Collection, patch: Partial<Collection>) =>
    commit({
      ...current.current,
      collections: current.current.collections.map((x) =>
        x.id === c.id ? { ...x, ...patch } : x,
      ),
    });
  const fields = (c: Collection) => [
    favoriteField,
    ...c.fields.filter((f) => f.kind !== "favorite"),
  ];
  const controls = (r: Item, c: Collection, only?: string[], detail = false) =>
    fields(c)
      .filter(
        (f) =>
          (!only?.length || only.includes(f.id)) &&
          (detail ||
            boolean(f) ||
            f.kind === "status" ||
            r.values[f.id] !== undefined),
      )
      .map((f) => (
        <FieldControl
          key={f.id}
          field={f}
          stored={
            f.id === "__favorite"
              ? { flag: { _0: favorite(r) } }
              : r.values[f.id]
          }
          language={language}
          save={(v) => changeValue(r, f, v)}
        />
      ));
  const row = (r: Item, c: Collection, only?: string[]) => (
    <article className="item-row" key={r.id}>
      <button className="row-title" onClick={() => openDetail("item", r.id)}>
        {r.title}
      </button>
      <div className="row-values">{controls(r, c, only)}</div>
    </article>
  );
  const saveEvent = (e: CalendarEvent) => {
    const old = current.current.events?.find((x) => x.id === e.id);
    if ((old && old.revision + 1 !== e.revision) || (!old && e.revision > 0)) {
      setNotice(
        t(
          "This event changed. Reopen it.",
          "Este evento ha cambiado. Ábrelo de nuevo.",
        ),
      );
      return false;
    }
    return commit({
      ...current.current,
      events: old
        ? current.current.events!.map((x) => (x.id === e.id ? e : x))
        : [...(current.current.events || []), e],
    });
  };
  const removeEvent = (e: CalendarEvent) => {
    if (
      current.current.events?.find((x) => x.id === e.id)?.revision !==
      e.revision
    ) {
      setNotice(
        t(
          "This event changed. Reopen it.",
          "Este evento ha cambiado. Ábrelo de nuevo.",
        ),
      );
      return;
    }
    commit({
      ...current.current,
      events: current.current.events?.filter((x) => x.id !== e.id),
    });
  };
  const calendar = (
    <BlueCalendar
      library={library}
      language={language}
      save={saveEvent}
      remove={removeEvent}
      openItem={(id) => openDetail("item", id)}
      onSelectDay={setSelectedDay}
    />
  );
  const requestDelete = (kind: string, id: string, title: string) => {
    const snapshot = JSON.stringify(current.current);
    setDeletion({
      title,
      perform: () => {
        if (JSON.stringify(current.current) !== snapshot) {
          setNotice(
            t(
              "Content changed. Please review before deleting.",
              "El contenido ha cambiado. Revísalo antes de borrar.",
            ),
          );
          setDeletion(undefined);
          return;
        }
        const next = { ...current.current };
        if (kind === "record")
          next.records = next.records.filter((r) => r.id !== id);
        if (kind === "note") next.notes = next.notes.filter((n) => n.id !== id);
        if (kind === "event")
          next.events = next.events?.filter((e) => e.id !== id);
        if (kind === "collection") {
          next.collections = next.collections.filter((c) => c.id !== id);
          next.records = next.records.filter((r) => r.collectionID !== id);
        }
        if (commit(next)) {
          setDeletion(undefined);
          setDetail(undefined);
          if (kind === "collection") navigate("collections");
        }
      },
    });
  };
  const addNote = () => {
    const n: Note = {
      id: uid(),
      title: userText(t("Untitled", "Sin título")),
      markdown: userText(""),
      revision: 0,
      updatedAt: now(),
    };
    if (commit({ ...current.current, notes: [...current.current.notes, n] })) {
      setCreating(false);
      openDetail("note", n.id);
    }
  };
  const addItem = () => {
    if (!collection) return;
    const r: Item = {
      id: uid(),
      collectionID: collection.id,
      title: t("Untitled", "Sin título"),
      markdown: userText(""),
      values: {},
      revision: 0,
      updatedAt: now(),
    };
    if (
      commit({ ...current.current, records: [...current.current.records, r] })
    )
      openDetail("item", r.id);
  };
  const addCollection = () => {
    const c: Collection = {
      id: uid(),
      title: userText(t("New collection", "Nueva colección")),
      symbol: "list.bullet",
      fields: [],
      createdAt: now(),
    };
    if (
      commit({
        ...current.current,
        collections: [...current.current.collections, c],
      })
    ) {
      setCreating(false);
      openCollection(c.id);
      setNewCollection(c.id);
    }
  };
  const exportData = () => {
    const url = URL.createObjectURL(
      new Blob([JSON.stringify(current.current, null, 2)], {
        type: "application/json",
      }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = "blue-library.json";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  async function send(e?: FormEvent) {
    e?.preventDefault();
    if (busy || !prompt.trim()) return;
    recognition.current?.stop();
    setBusy(true);
    setResult(undefined);
    setChatError("");
    const snapshot = JSON.stringify(current.current),
      sent = prompt.trim();
    try {
      const response = await fetch("/api/assistant", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prompt: sent,
          language,
          library: current.current,
          collectionID: collection?.id ?? conversationTarget.current.collection,
          previousRecord: note
            ? undefined
            : (item?.id ?? conversationTarget.current.record),
          noteID: item
            ? undefined
            : (note?.id ?? conversationTarget.current.note),
          surface: detail?.kind || (collection ? "collection" : scope),
          selectedDay,
          eventID: conversationTarget.current.event,
        }),
        signal: AbortSignal.timeout(105000),
      });
      const data = (await response.json()) as {
        library: Library;
        result: Result;
        error?: string;
      };
      if (!response.ok) throw new Error(data.error);
      if (JSON.stringify(current.current) !== snapshot)
        throw new Error("stale");
      if (!validLibrary(data.library)) throw new Error("invalid");
      if (JSON.stringify(data.library) !== snapshot && !commit(data.library))
        throw new Error("storage");
      const selection = data.result.selection?._0;
      const recordIDs = data.result.records?._0 ?? selection?.records ?? [];
      const noteIDs = data.result.notes?._0 ?? selection?.notes ?? [];
      const eventIDs = data.result.events?._0 ?? selection?.events ?? [];
      const resultCollection =
        data.result.collection?._0 ?? data.result.collectionView?._0;
      if (recordIDs.length === 1)
        conversationTarget.current = { record: recordIDs[0] };
      else if (noteIDs.length === 1)
        conversationTarget.current = { note: noteIDs[0] };
      else if (eventIDs.length === 1)
        conversationTarget.current = { event: eventIDs[0] };
      else if (resultCollection)
        conversationTarget.current = { collection: resultCollection };
      setResult(data.result);
      setResultSnapshot(JSON.stringify(current.current));
      setPrompt("");
    } catch (error) {
      setChatError(
        error instanceof Error && error.message === "stale"
          ? t(
              "Content changed. Send your request again.",
              "El contenido ha cambiado. Envía de nuevo la petición.",
            )
          : t(
              "Blue could not finish. Your message is still here.",
              "Blue no pudo terminar. Tu mensaje sigue aquí.",
            ),
      );
    } finally {
      setBusy(false);
    }
  }
  function dictate() {
    if (listening) {
      recognition.current?.stop();
      return;
    }
    const Speech =
      (window as any).SpeechRecognition ||
      (window as any).webkitSpeechRecognition;
    if (!Speech) {
      input.current?.focus();
      setChatError(
        t(
          "Use the microphone on your keyboard.",
          "Usa el micrófono de tu teclado.",
        ),
      );
      return;
    }
    const r = new Speech();
    r.lang = language === "es" ? "es-ES" : "en-US";
    r.interimResults = false;
    r.onresult = (e: any) =>
      setPrompt(
        (p) =>
          p + (p ? " " : "") + e.results[e.results.length - 1][0].transcript,
      );
    r.onend = () => setListening(false);
    r.onerror = () => {
      setListening(false);
      setChatError(t("Microphone unavailable.", "Micrófono no disponible."));
    };
    recognition.current = r;
    r.start();
    setListening(true);
  }
  const composer = (
    <form className="composer" onSubmit={send}>
      <textarea
        autoFocus
        ref={input}
        aria-label={t("Message Blue", "Mensaje para Blue")}
        placeholder={t("Ask Blue…", "Pídeselo a Blue…")}
        value={prompt}
        maxLength={2000}
        rows={1}
        onChange={(e) => setPrompt(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
            e.preventDefault();
            void send();
          }
        }}
      />
      <button
        type="button"
        className={`icon-button ${listening ? "active" : ""}`}
        aria-label={t("Dictate", "Dictar")}
        onClick={dictate}
      >
        {listening ? <MicOff size={20} /> : <Mic size={20} />}
      </button>
      <button
        className="round-dark"
        aria-label={t("Send", "Enviar")}
        disabled={busy || !prompt.trim()}
      >
        {busy ? (
          <LoaderCircle className="spin" size={20} />
        ) : (
          <ArrowUp size={20} />
        )}
      </button>
    </form>
  );
  const selection = result?.selection?._0;
  const resultRecords = selection?.records || result?.records?._0 || [];
  const resultNotes = selection?.notes || result?.notes?._0 || [];
  const resultCollections =
    selection?.collections ||
    (result?.collection
      ? [result.collection._0]
      : result?.collectionView
        ? [result.collectionView._0]
        : []);
  const resultEvents = selection?.events || result?.events?._0 || [];
  const confirmSchema = () => {
    const pending = result?.confirmCollectionChange?._0;
    if (!pending) return;
    if (JSON.stringify(current.current) !== resultSnapshot) {
      setChatError(
        t(
          "Content changed. Ask again.",
          "El contenido ha cambiado. Pídeselo de nuevo.",
        ),
      );
      return;
    }
    const next = {
      ...current.current,
      collections: current.current.collections.map((c) =>
        c.id === pending.original.id ? pending.proposed : c,
      ),
      records: current.current.records.map((r) =>
        r.collectionID === pending.original.id
          ? {
              ...r,
              values: Object.fromEntries(
                Object.entries(r.values).filter(([id, v]) => {
                  const f = pending.proposed.fields.find((f) => f.id === id);
                  return f && compatibleValue(f, v);
                }),
              ),
              revision: r.revision + 1,
              updatedAt: now(),
            }
          : r,
      ),
    };
    if (commit(next)) setResult({ collection: { _0: pending.proposed.id } });
  };
  const collections = library.collections.filter(
    (c) =>
      !search ||
      text(c.title, language)
        .toLocaleLowerCase()
        .includes(search.toLocaleLowerCase()),
  );
  const notes = library.notes.filter(
    (n) =>
      !search ||
      text(n.title, language)
        .toLocaleLowerCase()
        .includes(search.toLocaleLowerCase()),
  );
  return (
    <>
      <div className="app-shell">
        <header className="app-header">
          <button
            className="brand"
            aria-label={t("All of Blue", "Todo Blue")}
            onClick={() => navigate("all")}
          >
            <span className="brand-spark">✳</span> Blue
          </button>
          <div className="header-actions">
            <button
              className="icon-button"
              aria-label={t("Settings", "Ajustes")}
              onClick={() => setSettings(true)}
            >
              <Settings2 size={19} />
            </button>
          </div>
        </header>
        {notice && (
          <div className="notice" role="alert" onClick={() => setNotice("")}>
            {notice}
          </div>
        )}
        <main>
          {!ready ? (
            <LoaderCircle className="spin" />
          ) : (
            <>
              <div className="view-heading">
                {collection ? (
                  <EditableText
                    key={collection.id}
                    value={text(collection.title, language)}
                    label={t("Collection title", "Título de colección")}
                    large
                    save={(s) =>
                      changeCollection(collection, { title: userText(s) })
                    }
                  />
                ) : (
                  <h1>
                    {scope === "all"
                      ? t("Your space", "Tu espacio")
                      : scope === "notes"
                        ? t("Notes", "Notas")
                        : scope === "collections"
                          ? t("Collections", "Colecciones")
                          : t("Calendar", "Calendario")}
                  </h1>
                )}
                <div className="header-actions">
                  {collection && (
                    <>
                      <button
                        className="icon-button"
                        aria-label={t("Filters", "Filtros")}
                        onClick={() => setFilters(true)}
                      >
                        <SlidersHorizontal size={21} />
                      </button>
                      <button
                        className="icon-button danger"
                        aria-label={t(
                          "Delete collection",
                          "Eliminar colección",
                        )}
                        onClick={() =>
                          requestDelete(
                            "collection",
                            collection.id,
                            text(collection.title, language),
                          )
                        }
                      >
                        <Trash2 size={18} />
                      </button>
                    </>
                  )}
                  <button
                    className="round-dark"
                    aria-label={
                      scope === "calendar"
                        ? t("New event", "Nuevo evento")
                        : t("Add", "Añadir")
                    }
                    onClick={() =>
                      collection
                        ? addItem()
                        : scope === "calendar"
                          ? setEventEditor({ day: selectedDay })
                          : scope === "notes"
                            ? addNote()
                            : scope === "collections"
                              ? addCollection()
                              : setCreating(true)
                    }
                  >
                    <Plus size={23} />
                  </button>
                </div>
              </div>

              {collection ? (
                <>
                  <div className="collection-filters">
                    {fields(collection)
                      .filter((f) => boolean(f) || f.kind === "status")
                      .map((f) => (
                        <FieldControl
                          key={f.id}
                          field={f}
                          language={language}
                          filter
                          stored={
                            query.filters.find((x) => x.fieldID === f.id)?.flag
                              ? { flag: { _0: true } }
                              : query.filters.find((x) => x.fieldID === f.id)
                                    ?.text
                                ? {
                                    option: {
                                      _0: query.filters.find(
                                        (x) => x.fieldID === f.id,
                                      )!.text!,
                                    },
                                  }
                                : undefined
                          }
                          save={(v) =>
                            setQuery((q) => ({
                              ...q,
                              filters: [
                                ...q.filters.filter((x) => x.fieldID !== f.id),
                                ...(v?.flag?._0
                                  ? [{ fieldID: f.id, flag: true }]
                                  : v?.option
                                    ? [{ fieldID: f.id, text: v.option._0 }]
                                    : []),
                              ],
                            }))
                          }
                        />
                      ))}
                    {query.filters
                      .filter(
                        (f) =>
                          f.flag === undefined &&
                          !collection.fields.find(
                            (x) => x.id === f.fieldID && x.kind === "status",
                          ),
                      )
                      .map((f) => (
                        <button
                          className="active-filter"
                          key={f.fieldID}
                          aria-label={t("Remove filter", "Quitar filtro")}
                          onClick={() =>
                            setQuery((q) => ({
                              ...q,
                              filters: q.filters.filter(
                                (x) => x.fieldID !== f.fieldID,
                              ),
                            }))
                          }
                        >
                          <Symbol
                            name={
                              collection.fields.find((x) => x.id === f.fieldID)
                                ?.icon || "line.3.horizontal.decrease"
                            }
                          />
                          {f.minimum !== undefined ? "≥ " + f.minimum : f.text}
                        </button>
                      ))}
                  </div>
                  <div className="item-list">
                    {queryItems(
                      library.records.filter(
                        (r) => r.collectionID === collection.id,
                      ),
                      query,
                      search,
                      language,
                    ).map((r) => row(r, collection))}
                  </div>
                </>
              ) : (
                <>
                  {(scope === "all" || scope === "collections") && (
                    <section className="library-section">
                      {scope === "all" && (
                        <div className="section-label">
                          <h2>{t("Collections", "Colecciones")}</h2>
                        </div>
                      )}
                      <div className="collection-list">
                        {collections.map((c) => (
                          <button
                            className="collection-line"
                            key={c.id}
                            onClick={() => openCollection(c.id)}
                          >
                            <Symbol name={c.symbol} size={23} />
                            <strong>{text(c.title, language)}</strong>
                            <span className="count">
                              {
                                library.records.filter(
                                  (r) => r.collectionID === c.id,
                                ).length
                              }
                            </span>
                            <ChevronRight size={16} />
                          </button>
                        ))}
                      </div>
                    </section>
                  )}
                  {(scope === "all" || scope === "notes") && (
                    <section className="library-section">
                      {scope === "all" && (
                        <div className="section-label">
                          <h2>{t("Notes", "Notas")}</h2>
                        </div>
                      )}
                      <div className="note-list">
                        {notes.map((n) => (
                          <button
                            className="note-line"
                            key={n.id}
                            onClick={() => openDetail("note", n.id)}
                          >
                            <span>{text(n.title, language)}</span>
                          </button>
                        ))}
                      </div>
                    </section>
                  )}
                  {(scope === "all" || scope === "calendar") && (
                    <section className="library-section calendar-section">
                      {scope === "all" && (
                        <div className="section-label">
                          <h2>{t("Calendar", "Calendario")}</h2>
                          <button
                            className="icon-button"
                            aria-label={t("New event", "Nuevo evento")}
                            onClick={() => setEventEditor({ day: selectedDay })}
                          >
                            <Plus size={20} />
                          </button>
                        </div>
                      )}
                      {calendar}
                    </section>
                  )}
                </>
              )}
            </>
          )}
        </main>
      </div>
      <nav className="floating-nav" aria-label={t("Sections", "Secciones")}>
        {(["notes", "collections", "calendar"] as const).map((s) => {
          const Icon =
              s === "notes"
                ? FileText
                : s === "collections"
                  ? List
                  : CalendarDays,
            label =
              s === "notes"
                ? t("Notes", "Notas")
                : s === "collections"
                  ? t("Collections", "Colecciones")
                  : t("Calendar", "Calendario");
          return (
            <button
              key={s}
              className={scope === s && !chat ? "selected" : ""}
              aria-label={label}
              aria-current={scope === s && !chat ? "page" : undefined}
              onClick={() => navigate(s)}
            >
              <Icon size={20} />
              <span>{label}</span>
            </button>
          );
        })}
        <button
          className={`blue-tab ${chat ? "selected" : ""}`}
          aria-label={t("Talk to Blue", "Hablar con Blue")}
          onClick={() => setChat(!chat)}
        >
          <BlueMark small />
        </button>
      </nav>
      {item && (
        <Sheet
          title={item.title}
          heading={
            <EditableText
              value={item.title}
              label={t("Title", "Título")}
              large
              save={(title) => changeItem(item, { title })}
            />
          }
          close={() => setDetail(undefined)}
        >
          <div className="detail-properties">
            {controls(
              item,
              library.collections.find((c) => c.id === item.collectionID)!,
              undefined,
              true,
            )}
          </div>
          <MarkdownBody
            value={text(item.markdown, language)}
            language={language}
            save={(body) => changeItem(item, { markdown: userText(body) })}
          />
          {item.sources?.map((source) => (
            <section className="source-facts" key={source.url}>
              <p>{source.summary}</p>
              <a
                className="source-link"
                href={safeLink(source.url)}
                target="_blank"
                rel="noopener noreferrer"
              >
                {source.title}
              </a>
            </section>
          ))}
          <button
            className="icon-button danger"
            aria-label={t("Delete item", "Eliminar elemento")}
            onClick={() => requestDelete("record", item.id, item.title)}
          >
            <Trash2 size={20} />
          </button>
        </Sheet>
      )}
      {note && (
        <Sheet
          title={text(note.title, language)}
          heading={
            <EditableText
              value={text(note.title, language)}
              label={t("Title", "Título")}
              large
              save={(title) => changeNote(note, { title: userText(title) })}
            />
          }
          close={() => setDetail(undefined)}
        >
          <FieldControl
            field={favoriteField}
            stored={{ flag: { _0: !!note.favorite } }}
            language={language}
            save={(v) => changeNote(note, { favorite: v?.flag?._0 || false })}
          />
          <MarkdownBody
            value={text(note.markdown, language)}
            language={language}
            save={(body) => changeNote(note, { markdown: userText(body) })}
          />
          <button
            className="icon-button danger"
            aria-label={t("Delete note", "Eliminar nota")}
            onClick={() =>
              requestDelete("note", note.id, text(note.title, language))
            }
          >
            <Trash2 size={20} />
          </button>
        </Sheet>
      )}
      {creating && (
        <Sheet title={t("Add", "Añadir")} close={() => setCreating(false)}>
          <button className="menu-line" onClick={addNote}>
            <FileText />
            {t("Note", "Nota")}
          </button>
          <button className="menu-line" onClick={addCollection}>
            <List />
            {t("Collection", "Colección")}
          </button>
          <button
            className="menu-line"
            onClick={() => {
              setCreating(false);
              setEventEditor({ day: selectedDay });
            }}
          >
            <CalendarDays />
            {t("Event", "Evento")}
          </button>
        </Sheet>
      )}
      {newCollection && collection && (
        <Sheet
          title={t("Collection", "Colección")}
          close={() => setNewCollection(undefined)}
        >
          <EditableText
            value={text(collection.title, language)}
            large
            label={t("Collection title", "Título de colección")}
            save={(s) => changeCollection(collection, { title: userText(s) })}
          />
        </Sheet>
      )}
      {eventEditor && (
        <EventEditor
          key={eventEditor.event?.id || eventEditor.day}
          {...eventEditor}
          language={language}
          save={saveEvent}
          remove={removeEvent}
          close={() => setEventEditor(undefined)}
        />
      )}
      {filters && collection && (
        <Sheet
          title={t("Filter & sort", "Filtrar y ordenar")}
          close={() => setFilters(false)}
        >
          <input
            className="search-input"
            aria-label={t("Search collection", "Buscar en colección")}
            placeholder={t("Search…", "Buscar…")}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <div className="sort-options">
            {[
              { id: "title", label: userText(t("Title", "Título")) },
              ...collection.fields,
            ].map((f) => (
              <button
                className={query.sortField === f.id ? "selected" : ""}
                key={f.id}
                onClick={() =>
                  setQuery((q) => ({
                    ...q,
                    sortField: f.id,
                    ascending: q.sortField === f.id ? !q.ascending : true,
                  }))
                }
              >
                {text(f.label, language)}{" "}
                {query.sortField === f.id ? (query.ascending ? "↑" : "↓") : ""}
              </button>
            ))}
          </div>
          <div className="detail-properties">
            {fields(collection).map((f) => {
              const active = query.filters.find((x) => x.fieldID === f.id);
              const stored: Value | undefined = active?.flag
                ? { flag: { _0: true } }
                : active?.minimum !== undefined
                  ? { number: { _0: active.minimum } }
                  : active?.after !== undefined
                    ? { date: { _0: active.after } }
                    : active?.text
                      ? f.kind === "status"
                        ? { option: { _0: active.text } }
                        : { text: { _0: active.text } }
                      : undefined;
              return (
                <FieldControl
                  key={f.id}
                  field={f}
                  language={language}
                  filter
                  stored={stored}
                  save={(v) =>
                    setQuery((q) => ({
                      ...q,
                      filters: [
                        ...q.filters.filter((x) => x.fieldID !== f.id),
                        ...(v?.flag?._0
                          ? [{ fieldID: f.id, flag: true }]
                          : v?.number
                            ? [{ fieldID: f.id, minimum: v.number._0 }]
                            : v?.date
                              ? [{ fieldID: f.id, after: v.date._0 }]
                              : v?.option
                                ? [{ fieldID: f.id, text: v.option._0 }]
                                : v?.text
                                  ? [{ fieldID: f.id, text: v.text._0 }]
                                  : []),
                      ],
                    }))
                  }
                />
              );
            })}
          </div>
          {query.filters.length > 0 && (
            <button
              className="plain"
              onClick={() => setQuery((q) => ({ ...q, filters: [] }))}
            >
              {t("Clear filters", "Quitar filtros")}
            </button>
          )}
        </Sheet>
      )}
      {chat && (
        <Sheet
          title="Blue"
          close={() => {
            setChat(false);
            recognition.current?.stop();
          }}
          footer={composer}
        >
          <div className="assistant-result" aria-live="polite">
            {busy ? <LoaderCircle className="spin" /> : null}
            {chatError && <p role="alert">{chatError}</p>}
            {(selection?.answer || result?.answer?._0) && (
              <MarkdownBody
                language={language}
                value={selection?.answer || result?.answer?._0 || ""}
                readOnly
                save={() => {}}
              />
            )}
            {result?.message && (
              <p>
                {(strings as Record<string, { en: string; es: string }>)[
                  result.message._0
                ]?.[language] || t("Please clarify.", "Concreta un poco más.")}
              </p>
            )}
            {resultRecords.map((id) => {
              const r = library.records.find((r) => r.id === id),
                c =
                  r && library.collections.find((c) => c.id === r.collectionID);
              return r && c ? row(r, c, selection?.fields) : null;
            })}
            {resultNotes.map((id) => {
              const n = library.notes.find((n) => n.id === id);
              return n ? (
                <section key={id}>
                  <button
                    className="result-title"
                    onClick={() => openDetail("note", id)}
                  >
                    {text(n.title, language)}
                  </button>
                  <MarkdownBody
                    language={language}
                    value={text(n.markdown, language)}
                    save={(body) => changeNote(n, { markdown: userText(body) })}
                  />
                </section>
              ) : null;
            })}
            {resultCollections.map((id) => {
              const c = library.collections.find((c) => c.id === id);
              return c ? (
                <section key={id}>
                  <button
                    className="result-title"
                    onClick={() => openCollection(id)}
                  >
                    {text(c.title, language)}
                  </button>
                  {result?.collectionView
                    ? queryItems(
                        library.records.filter((r) => r.collectionID === id),
                        result.collectionView._1,
                        "",
                        language,
                      ).map((r) => row(r, c))
                    : null}
                </section>
              ) : null;
            })}
            {resultEvents.map((id) => {
              const e = library.events?.find((e) => e.id === id);
              return e ? (
                <button
                  className="agenda-entry"
                  key={id}
                  onClick={() => {
                    setChat(false);
                    setEventEditor({ event: e, day: e.day || selectedDay });
                  }}
                >
                  {e.title} ·{" "}
                  {new Date((e.date + 978307200) * 1000).toLocaleString(
                    language,
                  )}
                </button>
              ) : null;
            })}
            {result?.confirmCollectionChange && (
              <div className="confirmation-copy">
                <p>
                  {t(
                    "Remove these properties?",
                    "¿Eliminar estas propiedades?",
                  )}
                </p>
                <p>
                  {result.confirmCollectionChange._0.original.fields
                    .filter(
                      (f) =>
                        !result.confirmCollectionChange!._0.proposed.fields.some(
                          (x) => x.id === f.id,
                        ),
                    )
                    .map((f) => text(f.label, language))
                    .join(", ")}
                </p>
                <div className="confirmation-actions">
                  <button onClick={() => setResult(undefined)}>
                    {t("Keep", "Conservar")}
                  </button>
                  <button className="danger-button" onClick={confirmSchema}>
                    {t("Delete", "Eliminar")}
                  </button>
                </div>
              </div>
            )}
            {result?.confirmDeletion && (
              <button
                className="danger-button"
                onClick={() => {
                  if (JSON.stringify(current.current) !== resultSnapshot) {
                    setChatError(
                      t(
                        "Content changed. Ask again.",
                        "El contenido ha cambiado. Pídeselo de nuevo.",
                      ),
                    );
                    return;
                  }
                  requestDelete(
                    result.confirmDeletion!._0.kind,
                    result.confirmDeletion!._0.id,
                    t("Delete this content?", "¿Eliminar este contenido?"),
                  );
                }}
              >
                {t("Review deletion", "Revisar borrado")}
              </button>
            )}
          </div>
        </Sheet>
      )}
      {settings && (
        <Sheet
          title={t("Settings", "Ajustes")}
          close={() => setSettings(false)}
        >
          <div className="sort-options">
            <button
              className={language === "en" ? "selected" : ""}
              onClick={() => setLanguage("en")}
            >
              English
            </button>
            <button
              className={language === "es" ? "selected" : ""}
              onClick={() => setLanguage("es")}
            >
              Español
            </button>
          </div>
          <button className="menu-line" onClick={exportData}>
            <Download size={20} />
            {t("Export library", "Exportar biblioteca")}
          </button>
          <label className="filter-line">
            {t("Restore a backup", "Restaurar copia")}
            <input
              type="file"
              accept="application/json"
              onChange={async (e) => {
                const file = e.target.files?.[0];
                if (!file) return;
                try {
                  const next = JSON.parse(await file.text());
                  if (!validLibrary(next)) throw new Error();
                  const snapshot = JSON.stringify(current.current);
                  setDeletion({
                    title: t(
                      "Replace the library with this backup?",
                      "¿Sustituir la biblioteca por esta copia?",
                    ),
                    perform: () => {
                      if (JSON.stringify(current.current) !== snapshot) return;
                      if (commit(next)) {
                        setDeletion(undefined);
                        setSettings(false);
                        navigate("all");
                      }
                    },
                  });
                } catch {
                  setNotice(t("Invalid backup.", "Copia no válida."));
                }
              }}
            />
          </label>
          <p className="settings-copy">
            {t(
              "Saved in this browser. AI runs on your Mac; keep it awake. Calendar events do not ring.",
              "Se guarda en este navegador. La IA funciona en tu Mac; déjalo despierto. Los eventos del calendario no suenan.",
            )}
          </p>
        </Sheet>
      )}
      {deletion && (
        <Confirm
          language={language}
          title={deletion.title}
          confirm={deletion.perform}
          cancel={() => setDeletion(undefined)}
        />
      )}
    </>
  );
}
