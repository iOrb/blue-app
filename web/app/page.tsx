"use client";
import { useEffect, useRef, useState, type FormEvent } from "react";
import Markdown from "react-markdown";
import remarkGfm from "remark-gfm";
import {
  ArrowLeft,
  ArrowUp,
  ArrowDown,
  ArrowUpDown,
  ChevronRight,
  Download,
  FileText,
  List,
  Mic,
  MicOff,
  Plus,
  Search,
  Settings2,
  SlidersHorizontal,
  SquarePen,
  Trash2,
  Undo2,
  X,
  Check,
  LoaderCircle,
} from "lucide-react";
import {
  type Language,
  type Library,
  type Collection,
  type Item,
  type Note,
  type Field,
  type Query,
  emptyLibrary,
  uid,
  now,
  userText,
  text,
  boolean,
  favorite,
  favoriteField,
  value,
  displayValue,
  queryItems,
  validLibrary,
  safeLink,
} from "./blue-model";
import { BlueMark, Symbol, Indicator } from "./blue-icons";
import {
  words,
  Sheet,
  CollectionEditor,
  NoteEditor,
  ItemEditor,
  IndicatorEditor,
} from "./blue-editors";
import strings from "./native-strings.json";
const STORE = "blue.web.library.v2";
const baseQuery = (): Query => ({
  sortField: "title",
  ascending: true,
  filters: [],
});
type Route =
  { type: "library" } | { type: "collection" | "item" | "note"; id: string };
type Editing =
  | { type: "collection"; value?: Collection }
  | { type: "note"; value?: Note }
  | { type: "item"; collection: Collection; value?: Item }
  | { type: "indicator"; collection: Collection };
type Result = {
  answer?: { _0: string };
  message?: { _0: string };
  records?: { _0: string[]; edited: boolean };
  notes?: { _0: string[] };
  collection?: { _0: string };
  collectionView?: { _0: string; _1: Query & { search?: string } };
  confirmCollectionChange?: {
    _0: { original: Collection; proposed: Collection; revisions: unknown };
  };
};
type Recognition = {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  onresult:
    | ((event: {
        results: { isFinal: boolean; 0: { transcript: string } }[];
      }) => void)
    | null;
  onend: (() => void) | null;
  onerror: (() => void) | null;
  start: () => void;
  stop: () => void;
};
export default function Blue() {
  const [library, setLibrary] = useState<Library>(emptyLibrary);
  const current = useRef(library);
  const [ready, setReady] = useState(false);
  const [language, setLanguage] = useState<Language>("en");
  const [route, setRoute] = useState<Route>({ type: "library" });
  const [scope, setScope] = useState<"all" | "notes" | "collections">("all");
  const [starOnly, setStarOnly] = useState(false);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState<Query>(baseQuery);
  const [editing, setEditing] = useState<Editing>();
  const [settings, setSettings] = useState(false);
  const [filters, setFilters] = useState(false);
  const [history, setHistory] = useState<Library[]>([]);
  const [notice, setNotice] = useState("");
  const [chat, setChat] = useState(false);
  const [prompt, setPrompt] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<Result>();
  const [resultSnapshot, setResultSnapshot] = useState("");
  const [chatError, setChatError] = useState("");
  const [lastPrompt, setLastPrompt] = useState("");
  const [previous, setPrevious] = useState<string>();
  const [listening, setListening] = useState(false);
  const [canListen, setCanListen] = useState(false);
  const recognition = useRef<Recognition | undefined>(undefined);
  const input = useRef<HTMLTextAreaElement>(null);
  const chatBox = useRef<HTMLDivElement>(null);
  const t = (en: string, es: string) => words(language, en, es);
  useEffect(() => {
    try {
      const raw = localStorage.getItem(STORE);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (validLibrary(parsed)) {
          current.current = parsed;
          setLibrary(parsed);
        } else
          setNotice(
            "The saved library could not be read. Export or restore your backup. / No se pudo leer la biblioteca.",
          );
      }
      setPrompt(localStorage.getItem("blue.web.prompt") || "");
      const lang = localStorage.getItem("blue.web.language");
      if (lang === "es" || lang === "en") setLanguage(lang);
    } catch {
      setNotice(
        "Browser storage is unavailable. / El almacenamiento de Safari no está disponible.",
      );
    }
    setReady(true);
    setCanListen(
      !!(
        (window as unknown as Record<string, unknown>).SpeechRecognition ||
        (window as unknown as Record<string, unknown>).webkitSpeechRecognition
      ),
    );
    return () => recognition.current?.stop();
  }, []);
  useEffect(() => {
    document.documentElement.lang = language;
    if (ready)
      try {
        localStorage.setItem("blue.web.language", language);
      } catch {
        /* Library persistence reports storage errors separately. */
      }
  }, [language, ready]);
  useEffect(() => {
    function outside(e: PointerEvent) {
      if (chatBox.current && !chatBox.current.contains(e.target as Node)) {
        setChat(false);
        input.current?.blur();
      }
    }
    document.addEventListener("pointerdown", outside);
    return () => document.removeEventListener("pointerdown", outside);
  }, []);
  useEffect(() => {
    function receive(e: StorageEvent) {
      if (e.key === STORE && e.newValue) {
        try {
          const next = JSON.parse(e.newValue);
          if (validLibrary(next)) {
            current.current = next;
            setLibrary(next);
            setNotice(
              t(
                "Library updated in another tab.",
                "Biblioteca actualizada en otra pestaña.",
              ),
            );
          }
        } catch {
          /* Ignore invalid external storage. */
        }
      }
    }
    window.addEventListener("storage", receive);
    return () => window.removeEventListener("storage", receive);
  }, [language]);
  useEffect(() => {
    if (ready)
      try {
        localStorage.setItem("blue.web.prompt", prompt);
      } catch {}
  }, [prompt, ready]);
  const commit = (next: Library, remember = true) => {
    if (!validLibrary(next)) {
      setNotice(
        t("That change could not be saved.", "No se pudo guardar ese cambio."),
      );
      return false;
    }
    if (remember) setHistory((h) => [...h.slice(-9), current.current]);
    current.current = next;
    setLibrary(next);
    try {
      localStorage.setItem(STORE, JSON.stringify(next));
      return true;
    } catch {
      setNotice(
        t(
          "Storage is full or unavailable. Export a backup before closing this page.",
          "El almacenamiento está lleno o no está disponible. Exporta una copia antes de cerrar.",
        ),
      );
      return false;
    }
  };
  const navigate = (next: Route) => {
    setRoute(next);
    setSearch("");
    setChat(false);
    setQuery(baseQuery());
    window.scrollTo({ top: 0, behavior: "instant" });
  };
  const collection =
    route.type === "collection"
      ? library.collections.find((c) => c.id === route.id)
      : route.type === "item"
        ? library.collections.find(
            (c) =>
              c.id ===
              library.records.find((r) => r.id === route.id)?.collectionID,
          )
        : undefined;
  const item =
    route.type === "item"
      ? library.records.find((r) => r.id === route.id)
      : undefined;
  const note =
    route.type === "note"
      ? library.notes.find((n) => n.id === route.id)
      : undefined;
  const toggleItem = (r: Item, f: Field) => {
    const changed =
      f.id === "__favorite"
        ? { ...r, favorite: !favorite(r) }
        : {
            ...r,
            values: {
              ...r.values,
              [f.id]: { flag: { _0: !r.values[f.id]?.flag?._0 } },
            },
          };
    commit({
      ...current.current,
      records: current.current.records.map((x) =>
        x.id === r.id
          ? { ...changed, revision: r.revision + 1, updatedAt: now() }
          : x,
      ),
    });
  };
  const toggleNote = (n: Note) =>
    commit({
      ...current.current,
      notes: current.current.notes.map((x) =>
        x.id === n.id
          ? {
              ...n,
              favorite: !n.favorite,
              revision: n.revision + 1,
              updatedAt: now(),
            }
          : x,
      ),
    });
  const filterFlag = (f: Field) =>
    setQuery((q) => ({
      ...q,
      filters: q.filters.some((x) => x.fieldID === f.id)
        ? q.filters.filter((x) => x.fieldID !== f.id)
        : [...q.filters, { fieldID: f.id, flag: true }],
    }));
  const exportData = () => {
    const blob = new Blob([JSON.stringify(current.current, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `blue-web-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  const showEditor = (edit: Editing) => {
    setEditing(edit);
    setChat(false);
  };
  const saveNote = (n: Note) => {
    if (
      editing?.type === "note" &&
      editing.value &&
      current.current.notes.find((x) => x.id === n.id)?.revision !==
        editing.value.revision
    ) {
      setNotice(
        t(
          "This note changed. Copy your draft before reopening it.",
          "Esta nota ha cambiado. Copia tu borrador antes de abrirla de nuevo.",
        ),
      );
      return;
    }
    if (
      commit({
        ...current.current,
        notes: current.current.notes.some((x) => x.id === n.id)
          ? current.current.notes.map((x) => (x.id === n.id ? n : x))
          : [n, ...current.current.notes],
      })
    ) {
      setEditing(undefined);
      navigate({ type: "note", id: n.id });
    }
  };
  const saveItem = (r: Item) => {
    if (
      editing?.type === "item" &&
      editing.value &&
      current.current.records.find((x) => x.id === r.id)?.revision !==
        editing.value.revision
    ) {
      setNotice(
        t(
          "This item changed. Copy your draft before reopening it.",
          "Este elemento ha cambiado. Copia tu borrador antes de volver a abrirlo.",
        ),
      );
      return;
    }
    if (
      commit({
        ...current.current,
        records: current.current.records.some((x) => x.id === r.id)
          ? current.current.records.map((x) => (x.id === r.id ? r : x))
          : [...current.current.records, r],
      })
    ) {
      setEditing(undefined);
      navigate({ type: "item", id: r.id });
    }
  };
  const flags = (c: Collection) => [
    favoriteField,
    ...c.fields.filter((f) => boolean(f) && f.kind !== "favorite"),
  ];
  const properties = (r: Item, c: Collection) => (
    <dl className="properties">
      {c.fields
        .filter((f) => !boolean(f) && value(r.values[f.id]) !== "")
        .map((f) => (
          <div key={f.id}>
            <dt>{text(f.label, language)}</dt>
            <dd>{displayValue(r.values[f.id], f, language)}</dd>
          </div>
        ))}
    </dl>
  );
  const indicators = (r: Item, c: Collection) => (
    <div className="indicators">
      {flags(c).map((f) => (
        <Indicator
          key={f.id}
          field={f}
          active={
            f.id === "__favorite"
              ? favorite(r)
              : r.values[f.id]?.flag?._0 || false
          }
          language={language}
          onClick={() => toggleItem(r, f)}
        />
      ))}
    </div>
  );
  const renderItem = (r: Item, c: Collection) => (
    <article className="item-row" key={r.id}>
      <button
        className="row-content"
        onClick={() => navigate({ type: "item", id: r.id })}
      >
        <span className="row-title">{r.title}</span>
        {properties(r, c)}
        {text(r.markdown, language) && (
          <span className="row-excerpt">
            {text(r.markdown, language)
              .replace(/[#*`>]/g, "")
              .slice(0, 150)}
          </span>
        )}
      </button>
      {indicators(r, c)}
    </article>
  );
  const renderNote = (n: Note) => (
    <article className="note-card" key={n.id}>
      <button
        className="note-content"
        onClick={() => navigate({ type: "note", id: n.id })}
      >
        <FileText size={20} />
        <h3>{text(n.title, language)}</h3>
        <p>
          {text(n.markdown, language)
            .replace(/[#*`>]/g, "")
            .slice(0, 160) ||
            t(
              "A little space for your thoughts.",
              "Un espacio para tus ideas.",
            )}
        </p>
      </button>
      <Indicator
        field={favoriteField}
        active={!!n.favorite}
        language={language}
        onClick={() => toggleNote(n)}
      />
    </article>
  );
  const markdown = (body: string) => (
    <div className="markdown">
      <Markdown
        remarkPlugins={[remarkGfm]}
        components={{
          a: ({ href, children }) => (
            <a
              href={safeLink(href || "")}
              target="_blank"
              rel="noopener noreferrer"
            >
              {children}
            </a>
          ),
        }}
      >
        {body}
      </Markdown>
    </div>
  );
  async function send(e?: FormEvent) {
    e?.preventDefault();
    if (busy || !prompt.trim()) return;
    recognition.current?.stop();
    input.current?.blur();
    setBusy(true);
    setChat(true);
    setChatError("");
    setResult(undefined);
    const sent = prompt.trim();
    setLastPrompt(sent);
    const snapshot = JSON.stringify(current.current);
    try {
      const response = await fetch("/api/assistant", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prompt: sent,
          language,
          library: current.current,
          previousRecord: item?.id || previous,
          collectionID: collection?.id,
          noteID: note?.id,
        }),
        signal: AbortSignal.timeout(105000),
      });
      const data = (await response.json()) as {
        error?: string;
        library: unknown;
        result: Result;
      };
      if (!response.ok) throw new Error(data.error || "model_unavailable");
      if (JSON.stringify(current.current) !== snapshot)
        throw new Error("stale");
      if (!validLibrary(data.library)) throw new Error("invalid");
      if (JSON.stringify(data.library) !== snapshot && !commit(data.library))
        throw new Error("storage");
      const answer = data.result as Result;
      setResult(answer);
      setResultSnapshot(JSON.stringify(data.library));
      if (answer.records?._0.length === 1) setPrevious(answer.records._0[0]);
      setPrompt("");
    } catch (error) {
      const key = error instanceof Error ? error.message : "";
      setChatError(
        key === "stale"
          ? t(
              "Your library changed during this request. Send it again.",
              "La biblioteca cambió durante la petición. Vuelve a enviarla.",
            )
          : key === "busy"
            ? t(
                "The Mac is handling another request. Try again shortly.",
                "El Mac está atendiendo otra petición. Prueba en unos segundos.",
              )
            : key === "sign_in"
              ? t(
                  "Sign in with your ChatGPT account to use Blue.",
                  "Inicia sesión con tu cuenta de ChatGPT para usar Blue.",
                )
              : key === "storage"
                ? t(
                    "Export your library before continuing: browser storage is unavailable.",
                    "Exporta la biblioteca antes de continuar: no hay almacenamiento disponible.",
                  )
                : t(
                    "Blue could not connect to the Mac model. Keep the Mac awake and try again. Your draft is still here.",
                    "Blue no pudo conectar con el modelo del Mac. Mantén el Mac despierto y vuelve a probar. Tu borrador sigue aquí.",
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
    const speechWindow = window as unknown as {
      SpeechRecognition?: new () => Recognition;
      webkitSpeechRecognition?: new () => Recognition;
    };
    const Constructor =
      speechWindow.SpeechRecognition || speechWindow.webkitSpeechRecognition;
    if (!Constructor) {
      setChatError(
        t(
          "Use the microphone on your iPhone keyboard to dictate.",
          "Usa el micrófono del teclado del iPhone para dictar.",
        ),
      );
      setChat(true);
      input.current?.focus();
      return;
    }
    const r = new Constructor();
    recognition.current = r;
    r.lang = language === "es" ? "es-ES" : "en-US";
    r.continuous = false;
    r.interimResults = false;
    r.onresult = (e) => {
      const spoken = Array.from(e.results)
        .filter((x) => x.isFinal)
        .map((x) => x[0].transcript)
        .join(" ");
      setPrompt((p) => `${p}${p ? " " : ""}${spoken}`.slice(0, 2000));
    };
    r.onend = () => setListening(false);
    r.onerror = () => {
      setListening(false);
      setChatError(
        t(
          "Microphone unavailable. You can dictate with the keyboard microphone.",
          "El micrófono no está disponible. Puedes dictar desde el teclado.",
        ),
      );
    };
    try {
      r.start();
      setListening(true);
      setChat(true);
    } catch {
      r.onerror?.();
    }
  }
  function approveChange() {
    const pending = result?.confirmCollectionChange?._0;
    if (!pending) return;
    if (JSON.stringify(current.current) !== resultSnapshot) {
      setChatError(
        t(
          "The library changed. Ask Blue again.",
          "La biblioteca ha cambiado. Pídeselo de nuevo a Blue.",
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
                Object.entries(r.values).filter(([id]) =>
                  pending.proposed.fields.some((f) => f.id === id),
                ),
              ),
              revision: r.revision + 1,
              updatedAt: now(),
            }
          : r,
      ),
    };
    if (commit(next)) setResult({ collection: { _0: pending.proposed.id } });
  }
  const resultRecords =
    result?.records?._0
      .map((id) => library.records.find((r) => r.id === id))
      .filter((r): r is Item => !!r) || [];
  const resultNotes =
    result?.notes?._0
      .map((id) => library.notes.find((n) => n.id === id))
      .filter((n): n is Note => !!n) || [];
  const resultCollection = library.collections.find(
    (c) => c.id === (result?.collection?._0 || result?.collectionView?._0),
  );
  const resultKey = result?.message?._0;
  const message = resultKey
    ? (strings as Record<string, { en: string; es: string }>)[resultKey]?.[
        language
      ] ||
      t(
        "Blue could not complete that request. Try being more specific.",
        "Blue no pudo completar la petición. Prueba a concretarla un poco más.",
      )
    : "";
  const collectionItems = collection
    ? queryItems(
        library.records.filter((r) => r.collectionID === collection.id),
        query,
        search,
        language,
      )
    : [];
  const filteredNotes = library.notes.filter(
    (n) =>
      (!starOnly || n.favorite) &&
      text(n.title, language)
        .toLocaleLowerCase()
        .includes(search.toLocaleLowerCase()),
  );
  const filteredCollections = library.collections.filter((c) =>
    text(c.title, language)
      .toLocaleLowerCase()
      .includes(search.toLocaleLowerCase()),
  );
  const rootItems = library.records.filter(
    (r) =>
      (!starOnly || favorite(r)) &&
      r.title.toLocaleLowerCase().includes(search.toLocaleLowerCase()),
  );
  return (
    <>
      <div className="app-shell">
        <header className="app-header">
          <button
            className="brand"
            onClick={() => navigate({ type: "library" })}
            aria-label={t("Blue home", "Inicio de Blue")}
          >
            <BlueMark small />
            <span>
              blue<span className="brand-dot">.</span>
            </span>
          </button>
          <div className="header-actions">
            {history.length > 0 && (
              <button
                className="icon-button"
                title={t("Undo last change", "Deshacer último cambio")}
                aria-label={t("Undo last change", "Deshacer último cambio")}
                onClick={() => {
                  const old = history.at(-1)!;
                  if (commit(old, false)) setHistory((h) => h.slice(0, -1));
                }}
              >
                <Undo2 size={20} />
              </button>
            )}
            <button
              className="icon-button"
              aria-label={t("Settings", "Ajustes")}
              onClick={() => setSettings(true)}
            >
              <Settings2 size={21} />
            </button>
          </div>
        </header>
        {notice && (
          <div className="notice" role="alert">
            <span>{notice}</span>
            <button
              className="icon-button"
              aria-label={t("Dismiss", "Cerrar")}
              onClick={() => setNotice("")}
            >
              <X size={18} />
            </button>
          </div>
        )}
        <main>
          {!ready ? (
            <div className="empty">
              <LoaderCircle className="spin" />
              <p>{t("Opening your library…", "Abriendo tu biblioteca…")}</p>
            </div>
          ) : route.type === "library" ? (
            <>
              <div className="intro">
                <span className="eyebrow">
                  {t(
                    "A LITTLE SPACE FOR EVERYTHING",
                    "UN PEQUEÑO ESPACIO PARA TODO",
                  )}
                </span>
                <h1>{t("Your world, collected.", "Tu mundo, a mano.")}</h1>
                <p>
                  {t(
                    "A thought, a film, the next little thing. Make room for it.",
                    "Una idea, una peli, lo próximo que no quieres olvidar.",
                  )}
                </p>
              </div>
              <div className="library-toolbar">
                <nav
                  className="scope"
                  aria-label={t("Library views", "Vistas de biblioteca")}
                >
                  {(["all", "notes", "collections"] as const).map((s) => (
                    <button
                      key={s}
                      className={scope === s ? "selected" : ""}
                      aria-pressed={scope === s}
                      onClick={() => setScope(s)}
                    >
                      {s === "notes" ? (
                        <FileText size={17} />
                      ) : s === "collections" ? (
                        <List size={17} />
                      ) : (
                        <span className="four-dots">⁙</span>
                      )}
                      {s === "all"
                        ? t("Everything", "Todo")
                        : s === "notes"
                          ? t("Notes", "Notas")
                          : t("Collections", "Colecciones")}
                    </button>
                  ))}
                </nav>
                <Indicator
                  field={favoriteField}
                  active={starOnly}
                  language={language}
                  onClick={() => setStarOnly(!starOnly)}
                  label={t("Filter favorites", "Filtrar favoritos")}
                />
              </div>
              <div className="search-row">
                <label className="search">
                  <Search size={18} />
                  <input
                    aria-label={t("Search library", "Buscar en biblioteca")}
                    placeholder={t("Find something…", "Encuentra algo…")}
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                  />
                  {search && (
                    <button
                      className="icon-button"
                      aria-label={t("Clear search", "Borrar búsqueda")}
                      onClick={() => setSearch("")}
                    >
                      <X size={16} />
                    </button>
                  )}
                </label>
              </div>
              <div className="create-row">
                <button
                  className="create-button"
                  onClick={() => showEditor({ type: "note" })}
                >
                  <SquarePen size={19} />
                  {t("New note", "Nueva nota")}
                  <Plus size={17} />
                </button>
                <button
                  className="create-button"
                  onClick={() => showEditor({ type: "collection" })}
                >
                  <List size={19} />
                  {t("New collection", "Nueva colección")}
                  <Plus size={17} />
                </button>
              </div>
              {scope !== "notes" &&
                !starOnly &&
                filteredCollections.length > 0 && (
                  <section>
                    <div className="section-label">
                      <h2>{t("Collections", "Colecciones")}</h2>
                      <span>{filteredCollections.length}</span>
                    </div>
                    <div className="collection-grid">
                      {filteredCollections.map((c) => (
                        <button
                          className="collection-card"
                          key={c.id}
                          onClick={() =>
                            navigate({ type: "collection", id: c.id })
                          }
                        >
                          <span className="collection-symbol">
                            <Symbol name={c.symbol} size={24} />
                          </span>
                          <span>
                            <strong>{text(c.title, language)}</strong>
                            <small>
                              {
                                library.records.filter(
                                  (r) => r.collectionID === c.id,
                                ).length
                              }{" "}
                              {t("items", "elementos")}
                            </small>
                          </span>
                          <ChevronRight size={18} />
                        </button>
                      ))}
                    </div>
                  </section>
                )}
              {scope !== "collections" && filteredNotes.length > 0 && (
                <section>
                  <div className="section-label">
                    <h2>{t("Notes", "Notas")}</h2>
                    <span>{filteredNotes.length}</span>
                  </div>
                  <div className="note-grid">
                    {filteredNotes.map(renderNote)}
                  </div>
                </section>
              )}
              {scope !== "notes" &&
                (starOnly || search) &&
                rootItems.length > 0 && (
                  <section>
                    <div className="section-label">
                      <h2>{t("Items", "Elementos")}</h2>
                      <span>{rootItems.length}</span>
                    </div>
                    <div className="item-list">
                      {rootItems.map((r) =>
                        renderItem(
                          r,
                          library.collections.find(
                            (c) => c.id === r.collectionID,
                          )!,
                        ),
                      )}
                    </div>
                  </section>
                )}
              {!library.collections.length &&
                !library.notes.length &&
                !search &&
                !starOnly && (
                  <div className="empty welcome">
                    <BlueMark />
                    <h2>
                      {t(
                        "It starts with a little thought.",
                        "Todo empieza con una idea.",
                      )}
                    </h2>
                    <p>
                      {t(
                        "Write it down, make a list, or ask Blue to give it shape.",
                        "Escríbela, crea una lista o deja que Blue le dé forma.",
                      )}
                    </p>
                    <button
                      className="prompt-example"
                      onClick={() => {
                        setPrompt(
                          t(
                            "Save Interstellar in a Movies collection.",
                            "Guarda Interstellar en una colección Películas.",
                          ),
                        );
                        setChat(true);
                        input.current?.focus();
                      }}
                    >
                      {t(
                        "“Let’s start a movie list”",
                        "«Vamos a crear una lista de pelis»",
                      )}
                      <ArrowUp size={16} />
                    </button>
                  </div>
                )}
              {(starOnly || search) &&
                !filteredNotes.length &&
                !rootItems.length &&
                !(!starOnly && filteredCollections.length) && (
                  <div className="empty">
                    <Search />
                    <p>
                      {t(
                        "Nothing here yet. Try another filter.",
                        "Aún no hay nada aquí. Prueba otro filtro.",
                      )}
                    </p>
                  </div>
                )}
            </>
          ) : route.type === "collection" && collection ? (
            <>
              <button
                className="back"
                onClick={() => navigate({ type: "library" })}
              >
                <ArrowLeft size={18} />
                {t("Your library", "Tu biblioteca")}
              </button>
              <div className="detail-heading">
                <div className="title-with-symbol">
                  <span className="collection-symbol large">
                    <Symbol name={collection.symbol} size={30} />
                  </span>
                  <div>
                    <span className="eyebrow">
                      {t("COLLECTION", "COLECCIÓN")}
                    </span>
                    <h1>{text(collection.title, language)}</h1>
                  </div>
                </div>
                <button
                  className="icon-button"
                  aria-label={t("Edit collection", "Editar colección")}
                  onClick={() =>
                    showEditor({ type: "collection", value: collection })
                  }
                >
                  <SquarePen size={20} />
                </button>
              </div>
              <div className="collection-tools">
                <div className="filter-indicators">
                  {flags(collection).map((f) => (
                    <Indicator
                      key={f.id}
                      field={f}
                      active={query.filters.some((x) => x.fieldID === f.id)}
                      language={language}
                      label={`${t("Filter", "Filtrar")}: ${text(f.label, language)}`}
                      onClick={() => filterFlag(f)}
                    />
                  ))}
                </div>
                <div className="header-actions">
                  <button
                    className={`icon-button ${filters ? "selected" : ""}`}
                    aria-label={t("Filter and sort", "Filtrar y ordenar")}
                    onClick={() => setFilters(true)}
                  >
                    <SlidersHorizontal size={20} />
                  </button>
                  <button
                    className="primary compact"
                    onClick={() => showEditor({ type: "item", collection })}
                  >
                    <Plus size={19} />
                    <span>{t("Add", "Añadir")}</span>
                  </button>
                </div>
              </div>
              {query.filters.some((f) => f.flag === undefined) && (
                <div className="active-filters">
                  {query.filters
                    .filter((f) => f.flag === undefined)
                    .map((f) => (
                      <button
                        className="choice selected"
                        key={f.fieldID}
                        onClick={() =>
                          setQuery((q) => ({
                            ...q,
                            filters: q.filters.filter(
                              (x) => x.fieldID !== f.fieldID,
                            ),
                          }))
                        }
                      >
                        {text(
                          collection.fields.find((x) => x.id === f.fieldID)
                            ?.label || userText(f.fieldID),
                          language,
                        )}
                        :{" "}
                        {f.text || `${f.minimum ?? "−∞"} – ${f.maximum ?? "∞"}`}
                        <X size={14} />
                      </button>
                    ))}
                </div>
              )}
              <label className="search">
                <Search size={18} />
                <input
                  placeholder={t("Find an item…", "Busca un elemento…")}
                  aria-label={t("Search items", "Buscar elementos")}
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                />
              </label>
              <div className="section-label">
                <span>
                  {collectionItems.length} {t("items", "elementos")}
                </span>
                <button
                  className="text-button"
                  onClick={() => showEditor({ type: "indicator", collection })}
                >
                  <Plus size={15} />
                  {t("Indicator", "Indicador")}
                </button>
              </div>
              <div className="item-list">
                {collectionItems.map((r) => renderItem(r, collection))}
              </div>
              {!collectionItems.length && (
                <div className="empty">
                  <Symbol name={collection.symbol} size={34} />
                  <h2>
                    {t("Room for something good.", "Aquí cabe algo bueno.")}
                  </h2>
                  <p>
                    {t(
                      "Add an item or tell Blue what belongs here.",
                      "Añade un elemento o cuéntale a Blue qué quieres guardar.",
                    )}
                  </p>
                </div>
              )}
            </>
          ) : route.type === "note" && note ? (
            <>
              <button
                className="back"
                onClick={() => navigate({ type: "library" })}
              >
                <ArrowLeft size={18} />
                {t("Your library", "Tu biblioteca")}
              </button>
              <div className="detail-heading">
                <div>
                  <span className="eyebrow">{t("NOTE", "NOTA")}</span>
                  <h1>{text(note.title, language)}</h1>
                </div>
                <div className="header-actions">
                  <Indicator
                    field={favoriteField}
                    active={!!note.favorite}
                    language={language}
                    onClick={() => toggleNote(note)}
                  />
                  <button
                    className="icon-button"
                    aria-label={t("Edit note", "Editar nota")}
                    onClick={() => showEditor({ type: "note", value: note })}
                  >
                    <SquarePen size={20} />
                  </button>
                </div>
              </div>
              {markdown(
                text(note.markdown, language) ||
                  t(
                    "*Your note is ready for a thought.*",
                    "*Tu nota está lista para una idea.*",
                  ),
              )}
              <button
                className="danger text-button"
                onClick={() => {
                  commit({
                    ...current.current,
                    notes: current.current.notes.filter(
                      (n) => n.id !== note.id,
                    ),
                  });
                  navigate({ type: "library" });
                  setNotice(
                    t(
                      "Note deleted. Use Undo to restore it.",
                      "Nota eliminada. Pulsa Deshacer para recuperarla.",
                    ),
                  );
                }}
              >
                <Trash2 size={16} />
                {t("Delete note", "Eliminar nota")}
              </button>
            </>
          ) : route.type === "item" && item && collection ? (
            <>
              <button
                className="back"
                onClick={() =>
                  navigate({ type: "collection", id: collection.id })
                }
              >
                <ArrowLeft size={18} />
                <Symbol name={collection.symbol} size={16} />
                {text(collection.title, language)}
              </button>
              <div className="detail-heading">
                <h1>{item.title}</h1>
                <button
                  className="icon-button"
                  aria-label={t("Edit item", "Editar elemento")}
                  onClick={() =>
                    showEditor({ type: "item", value: item, collection })
                  }
                >
                  <SquarePen size={20} />
                </button>
              </div>
              <div className="indicator-meanings">
                {flags(collection).map((f) => (
                  <div key={f.id}>
                    <Indicator
                      field={f}
                      active={
                        f.id === "__favorite"
                          ? favorite(item)
                          : item.values[f.id]?.flag?._0 || false
                      }
                      language={language}
                      onClick={() => toggleItem(item, f)}
                    />
                    <span>{text(f.label, language)}</span>
                  </div>
                ))}
              </div>
              <div className="detail-properties">
                {properties(item, collection)}
              </div>
              {markdown(text(item.markdown, language))}
              {item.sources?.length ? (
                <section className="sources">
                  <h2>{t("Sources", "Fuentes")}</h2>
                  {item.sources.map((source, i) => (
                    <a
                      key={i}
                      href={safeLink(source.url)}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      {source.title}
                      <ChevronRight size={16} />
                    </a>
                  ))}
                </section>
              ) : null}
              <button
                className="danger text-button"
                onClick={() => {
                  commit({
                    ...current.current,
                    records: current.current.records.filter(
                      (r) => r.id !== item.id,
                    ),
                  });
                  navigate({ type: "collection", id: collection.id });
                  setNotice(
                    t(
                      "Item deleted. Use Undo to restore it.",
                      "Elemento eliminado. Pulsa Deshacer para recuperarlo.",
                    ),
                  );
                }}
              >
                <Trash2 size={16} />
                {t("Delete item", "Eliminar elemento")}
              </button>
            </>
          ) : (
            <div className="empty">
              <p>
                {t(
                  "This item is no longer here.",
                  "Este elemento ya no está aquí.",
                )}
              </p>
              <button
                className="primary"
                onClick={() => navigate({ type: "library" })}
              >
                {t("Open library", "Abrir biblioteca")}
              </button>
            </div>
          )}
        </main>
        <footer className="page-footer">
          <span>blue.</span>
          <span>{t("A space of your own.", "Un espacio muy tuyo.")}</span>
        </footer>
      </div>
      <div className={`assistant-wrap ${chat ? "expanded" : ""}`} ref={chatBox}>
        {chat && (
          <section
            className="assistant-panel"
            aria-label={t("Blue assistant", "Asistente Blue")}
          >
            <div className="assistant-title">
              <div>
                <span className={`status-dot ${busy ? "thinking" : ""}`} />
                <strong>
                  {busy
                    ? t("Blue is thinking…", "Blue está pensando…")
                    : t("A little help from Blue", "Una mano de Blue")}
                </strong>
              </div>
              <button
                className="icon-button"
                aria-label={t("Close chat", "Cerrar chat")}
                onClick={() => {
                  setChat(false);
                  input.current?.blur();
                }}
              >
                <X size={18} />
              </button>
            </div>
            <div className="assistant-content" aria-live="polite">
              {lastPrompt && <p className="your-prompt">{lastPrompt}</p>}
              {busy ? (
                <div className="thinking-line">
                  <LoaderCircle className="spin" size={18} />
                  {t(
                    "Working with the model on your Mac…",
                    "Trabajando con el modelo de tu Mac…",
                  )}
                </div>
              ) : chatError ? (
                <p className="chat-error" role="alert">
                  {chatError}
                </p>
              ) : result ? (
                <>
                  {result.answer && markdown(result.answer._0)}
                  {message && <p>{message}</p>}
                  {resultRecords.map((r) => (
                    <button
                      className="result-card"
                      key={r.id}
                      onClick={() => navigate({ type: "item", id: r.id })}
                    >
                      <span>
                        <strong>{r.title}</strong>
                        {properties(
                          r,
                          library.collections.find(
                            (c) => c.id === r.collectionID,
                          )!,
                        )}
                      </span>
                      <ChevronRight size={18} />
                    </button>
                  ))}
                  {resultNotes.map((n) => (
                    <button
                      className="result-card"
                      key={n.id}
                      onClick={() => navigate({ type: "note", id: n.id })}
                    >
                      <FileText size={18} />
                      <strong>{text(n.title, language)}</strong>
                      <ChevronRight size={18} />
                    </button>
                  ))}
                  {resultCollection && (
                    <button
                      className="result-card"
                      onClick={() => {
                        navigate({
                          type: "collection",
                          id: resultCollection.id,
                        });
                        if (result?.collectionView) {
                          setQuery(result.collectionView._1);
                          setSearch(result.collectionView._1.search || "");
                        }
                      }}
                    >
                      <Symbol name={resultCollection.symbol} />
                      <strong>{text(resultCollection.title, language)}</strong>
                      <ChevronRight size={18} />
                    </button>
                  )}
                  {result.confirmCollectionChange && (
                    <div className="confirmation">
                      <h3>
                        {t(
                          "Remove saved information?",
                          "¿Eliminar información guardada?",
                        )}
                      </h3>
                      <p>
                        {result.confirmCollectionChange._0.original.fields
                          .filter(
                            (f) =>
                              !result.confirmCollectionChange!._0.proposed.fields.some(
                                (p) => p.id === f.id,
                              ),
                          )
                          .map((f) => text(f.label, language))
                          .join(", ")}
                      </p>
                      <p className="muted">
                        {t(
                          "These fields and their values will be removed from every item in this collection.",
                          "Estos campos y sus valores se eliminarán de todos los elementos de la colección.",
                        )}
                      </p>
                      <div className="choice-row">
                        <button className="primary" onClick={approveChange}>
                          {t("Remove fields", "Eliminar campos")}
                        </button>
                        <button
                          className="choice"
                          onClick={() => setResult(undefined)}
                        >
                          {t("Keep them", "Conservarlos")}
                        </button>
                      </div>
                    </div>
                  )}
                </>
              ) : (
                <>
                  <p>
                    {t(
                      "Tell me what to keep, find or change. I can shape your collections as you go.",
                      "Dime qué guardar, encontrar o cambiar. Puedo dar forma a tus colecciones sobre la marcha.",
                    )}
                  </p>
                  <div className="suggestions">
                    {[
                      t(
                        "Create a note with my weekend ideas",
                        "Crea una nota con ideas para el finde",
                      ),
                      collection
                        ? t(
                            "Add a 🗿 indicator called Bass",
                            "Añade un indicador 🗿 llamado Bass",
                          )
                        : t(
                            "Save Interstellar in a Movies collection",
                            "Guarda Interstellar en una colección Películas",
                          ),
                    ].map((p) => (
                      <button
                        key={p}
                        onClick={() => {
                          setPrompt(p);
                          input.current?.focus();
                        }}
                      >
                        {p}
                        <ArrowUp size={15} />
                      </button>
                    ))}
                  </div>
                  <p className="microcopy">
                    {t(
                      "AI runs on your Mac. Keep it awake.",
                      "La IA funciona en tu Mac. Déjalo despierto.",
                    )}
                  </p>
                </>
              )}
            </div>
          </section>
        )}
        <form className="assistant-dock" onSubmit={send}>
          <button
            type="button"
            className="assistant-character"
            aria-label={t("Open Blue chat", "Abrir chat de Blue")}
            onClick={() => {
              setChat(!chat);
              if (!chat) input.current?.focus();
            }}
          >
            <BlueMark small />
          </button>
          <textarea
            ref={input}
            aria-label={t("Message Blue", "Mensaje para Blue")}
            placeholder={
              listening
                ? t("Listening…", "Escuchando…")
                : t("Tell Blue something…", "Cuéntale algo a Blue…")
            }
            value={prompt}
            maxLength={2000}
            rows={1}
            onFocus={() => setChat(true)}
            onChange={(e) => setPrompt(e.target.value)}
            onKeyDown={(e) => {
              if (
                e.key === "Enter" &&
                !e.shiftKey &&
                !e.nativeEvent.isComposing
              ) {
                e.preventDefault();
                void send();
              }
            }}
          />
          <button
            type="button"
            className={`icon-button mic ${listening ? "recording" : ""}`}
            aria-label={
              listening
                ? t("Stop dictation", "Detener dictado")
                : t("Dictate to Blue", "Dictar a Blue")
            }
            title={
              canListen
                ? t("Browser dictation", "Dictado del navegador")
                : t("Use keyboard dictation", "Usa el dictado del teclado")
            }
            onClick={dictate}
          >
            {listening ? <MicOff size={20} /> : <Mic size={20} />}
          </button>
          <button
            className="send"
            aria-label={t("Send to Blue", "Enviar a Blue")}
            disabled={busy || !prompt.trim()}
            type="submit"
          >
            {busy ? (
              <LoaderCircle className="spin" size={20} />
            ) : (
              <ArrowUp size={20} />
            )}
          </button>
        </form>
      </div>
      {editing?.type === "collection" && (
        <CollectionEditor
          language={language}
          collection={editing.value}
          close={() => setEditing(undefined)}
          save={(c) => {
            if (
              commit({
                ...current.current,
                collections: current.current.collections.some(
                  (x) => x.id === c.id,
                )
                  ? current.current.collections.map((x) =>
                      x.id === c.id ? c : x,
                    )
                  : [...current.current.collections, c],
              })
            ) {
              setEditing(undefined);
              navigate({ type: "collection", id: c.id });
            }
          }}
        />
      )}
      {editing?.type === "note" && (
        <NoteEditor
          language={language}
          note={editing.value}
          save={saveNote}
          close={() => setEditing(undefined)}
        />
      )}{" "}
      {editing?.type === "item" && (
        <ItemEditor
          language={language}
          collection={editing.collection}
          item={editing.value}
          save={saveItem}
          close={() => setEditing(undefined)}
        />
      )}{" "}
      {editing?.type === "indicator" && (
        <IndicatorEditor
          language={language}
          close={() => setEditing(undefined)}
          save={(f) => {
            if (
              commit({
                ...current.current,
                collections: current.current.collections.map((c) =>
                  c.id === editing.collection.id
                    ? { ...c, fields: [...c.fields, f] }
                    : c,
                ),
              })
            )
              setEditing(undefined);
          }}
        />
      )}
      {settings && (
        <Sheet
          title={t("Your Blue", "Tu Blue")}
          close={() => setSettings(false)}
        >
          <div className="settings-intro">
            <BlueMark />
            <h3>
              {t("A little space. All yours.", "Un pequeño espacio. Muy tuyo.")}
            </h3>
          </div>
          <label>{t("Language", "Idioma")}</label>
          <div className="choice-row">
            <button
              className={`choice ${language === "en" ? "selected" : ""}`}
              aria-pressed={language === "en"}
              onClick={() => setLanguage("en")}
            >
              English
            </button>
            <button
              className={`choice ${language === "es" ? "selected" : ""}`}
              aria-pressed={language === "es"}
              onClick={() => setLanguage("es")}
            >
              Español
            </button>
          </div>
          <div className="settings-section">
            <h3>{t("Keep your thoughts safe", "Cuida tus ideas")}</h3>
            <p>
              {t(
                "Your library is stored in this browser. It is separate from the iPhone app and other browsers. Export a backup before clearing Safari data.",
                "Tu biblioteca se guarda en este navegador. Es independiente de la app del iPhone y de otros navegadores. Exporta una copia antes de borrar los datos de Safari.",
              )}
            </p>
            <button className="create-button" onClick={exportData}>
              <Download size={18} />
              {t("Export library", "Exportar biblioteca")}
            </button>
            <label className="import-label">
              {t(
                "Restore a Blue web backup",
                "Restaurar una copia de Blue web",
              )}
              <input
                type="file"
                accept="application/json,.json"
                onChange={async (e) => {
                  const file = e.target.files?.[0];
                  if (!file) return;
                  try {
                    if (file.size > 2_000_000) throw new Error();
                    const next = JSON.parse(await file.text());
                    if (!validLibrary(next)) throw new Error();
                    if (
                      window.confirm(
                        t(
                          "Replace this browser’s library with this backup?",
                          "¿Reemplazar la biblioteca de este navegador por esta copia?",
                        ),
                      )
                    ) {
                      commit(next);
                      navigate({ type: "library" });
                      setSettings(false);
                    }
                  } catch {
                    setNotice(
                      t(
                        "That file is not a valid Blue web backup.",
                        "El archivo no es una copia válida de Blue web.",
                      ),
                    );
                  }
                  e.target.value = "";
                }}
              />
            </label>
          </div>
          <div className="settings-section">
            <h3>{t("On your Home Screen", "En tu pantalla de inicio")}</h3>
            <p>
              {t(
                "In Safari, tap Share → Add to Home Screen. Open this same site with your ChatGPT account.",
                "En Safari, pulsa Compartir → Añadir a pantalla de inicio. Abre este sitio con tu cuenta de ChatGPT.",
              )}
            </p>
          </div>
          <div className="settings-section">
            <h3>{t("About this preview", "Sobre esta prueba")}</h3>
            <p>
              {t(
                "AI requests send a snapshot of this web library through the protected site to your Mac’s Apple model. The Mac must remain awake. Web enrichment can look up public topic titles on Wikipedia. Browser dictation uses your browser’s speech service.",
                "Las peticiones de IA envían una copia de esta biblioteca web a través del sitio protegido al modelo de Apple en tu Mac. El Mac debe seguir despierto. El enriquecimiento web puede buscar títulos públicos en Wikipedia. El dictado utiliza el servicio de voz de tu navegador.",
              )}
            </p>
            <p>
              {t(
                "This preview covers notes and collections. Native alarms and device sync are not available here.",
                "Esta prueba incluye notas y colecciones. Las alarmas nativas y la sincronización entre dispositivos no están disponibles aquí.",
              )}
            </p>
          </div>
        </Sheet>
      )}
      {filters && collection && (
        <Sheet
          title={t("Make it your view", "A tu manera")}
          close={() => setFilters(false)}
        >
          <label>{t("Sort by", "Ordenar por")}</label>
          <div className="choice-row">
            {[
              { id: "title", label: userText(t("Title", "Título")) },
              ...collection.fields.filter((f) => !boolean(f)),
            ].map((f) => (
              <button
                className={`choice ${query.sortField === f.id ? "selected" : ""}`}
                aria-pressed={query.sortField === f.id}
                key={f.id}
                onClick={() => setQuery((q) => ({ ...q, sortField: f.id }))}
              >
                {text(f.label, language)}
              </button>
            ))}
            <button
              className="choice"
              onClick={() =>
                setQuery((q) => ({ ...q, ascending: !q.ascending }))
              }
            >
              {query.ascending ? (
                <ArrowUp size={16} />
              ) : (
                <ArrowDown size={16} />
              )}{" "}
              {query.ascending
                ? t("Ascending", "Ascendente")
                : t("Descending", "Descendente")}
            </button>
          </div>
          {collection.fields
            .filter((f) => !boolean(f))
            .map((f) => (
              <div className="filter-field" key={f.id}>
                <label>{text(f.label, language)}</label>
                {f.kind === "status" ? (
                  <div className="choice-row">
                    {f.options.map((o) => (
                      <button
                        className={`choice ${query.filters.some((x) => x.fieldID === f.id && x.text === o.id) ? "selected" : ""}`}
                        key={o.id}
                        onClick={() =>
                          setQuery((q) => ({
                            ...q,
                            filters: q.filters.some(
                              (x) => x.fieldID === f.id && x.text === o.id,
                            )
                              ? q.filters.filter((x) => x.fieldID !== f.id)
                              : [
                                  ...q.filters.filter(
                                    (x) => x.fieldID !== f.id,
                                  ),
                                  { fieldID: f.id, text: o.id },
                                ],
                          }))
                        }
                      >
                        {text(o.label, language)}
                      </button>
                    ))}
                  </div>
                ) : ["number", "rating"].includes(f.kind) ? (
                  <div className="range-inputs">
                    {(["minimum", "maximum"] as const).map((bound) => (
                      <input
                        key={bound}
                        type="number"
                        step="any"
                        placeholder={
                          bound === "minimum"
                            ? t("Min", "Mín")
                            : t("Max", "Máx")
                        }
                        aria-label={`${text(f.label, language)} ${bound}`}
                        value={
                          query.filters.find((x) => x.fieldID === f.id)?.[
                            bound
                          ] ?? ""
                        }
                        onChange={(e) =>
                          setQuery((q) => {
                            const filter = {
                              ...q.filters.find((x) => x.fieldID === f.id),
                              fieldID: f.id,
                              [bound]:
                                e.target.value === ""
                                  ? undefined
                                  : Number(e.target.value),
                            };
                            return {
                              ...q,
                              filters: [
                                ...q.filters.filter((x) => x.fieldID !== f.id),
                                ...(filter.minimum === undefined &&
                                filter.maximum === undefined
                                  ? []
                                  : [filter]),
                              ],
                            };
                          })
                        }
                      />
                    ))}
                  </div>
                ) : f.kind !== "date" ? (
                  <input
                    value={
                      query.filters.find((x) => x.fieldID === f.id)?.text || ""
                    }
                    placeholder={t("Contains…", "Contiene…")}
                    onChange={(e) =>
                      setQuery((q) => ({
                        ...q,
                        filters: [
                          ...q.filters.filter((x) => x.fieldID !== f.id),
                          ...(e.target.value
                            ? [{ fieldID: f.id, text: e.target.value }]
                            : []),
                        ],
                      }))
                    }
                  />
                ) : (
                  <p className="muted">
                    {t(
                      "Ask Blue to filter by date.",
                      "Pide a Blue que filtre por fecha.",
                    )}
                  </p>
                )}
              </div>
            ))}
          <button className="primary" onClick={() => setFilters(false)}>
            <Check size={18} />
            {t("Done", "Listo")}
          </button>
        </Sheet>
      )}
    </>
  );
}
