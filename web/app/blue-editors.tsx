"use client";
import {
  useState,
  useEffect,
  useRef,
  type FormEvent,
  type ReactNode,
} from "react";
import { X, Trash2, Save, Plus } from "lucide-react";
import { Indicator, Symbol } from "./blue-icons";
import {
  type Language,
  type Library,
  type Note,
  type Item,
  type Collection,
  type Field,
  type Value,
  text,
  userText,
  uid,
  now,
  boolean,
  favorite,
  favoriteField,
  value,
  colors,
} from "./blue-model";
export const words = (l: Language, en: string, es: string) =>
  l === "es" ? es : en;
function useDraft<T>(key: string, initial: T) {
  const [draft, setDraft] = useState<T>(() => {
    try {
      const saved = sessionStorage.getItem(key);
      return saved === null ? initial : (JSON.parse(saved) as T);
    } catch {
      return initial;
    }
  });
  useEffect(() => {
    try {
      sessionStorage.setItem(key, JSON.stringify(draft));
    } catch {}
  }, [key, draft]);
  const clear = () => {
    try {
      sessionStorage.removeItem(key);
    } catch {}
  };
  return [draft, setDraft, clear] as const;
}
export function Sheet({
  title,
  close,
  children,
}: {
  title: string;
  close: () => void;
  children: ReactNode;
}) {
  const panel = useRef<HTMLElement>(null);
  return (
    <div className="sheet-shade" onClick={close}>
      <section
        ref={panel}
        onKeyDown={(e) => {
          if (e.key === "Escape") {
            e.preventDefault();
            close();
          }
          if (e.key === "Tab") {
            const focusable = panel.current?.querySelectorAll<HTMLElement>(
              "button:not([disabled]), input, textarea, a[href]",
            );
            if (focusable?.length) {
              const first = focusable[0],
                last = focusable[focusable.length - 1];
              if (e.shiftKey && document.activeElement === first) {
                e.preventDefault();
                last.focus();
              } else if (!e.shiftKey && document.activeElement === last) {
                e.preventDefault();
                first.focus();
              }
            }
          }
        }}
        className="sheet"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="sheet-heading">
          <h2>{title}</h2>
          <button
            className="icon-button"
            aria-label="Close / Cerrar"
            onClick={close}
          >
            <X />
          </button>
        </div>
        {children}
      </section>
    </div>
  );
}
export function CollectionEditor({
  collection,
  language,
  save,
  close,
}: {
  collection?: Collection;
  language: Language;
  save: (c: Collection) => void;
  close: () => void;
}) {
  const [title, setTitle] = useState(
    collection ? text(collection.title, language) : "",
  );
  const [symbol, setSymbol] = useState(collection?.symbol || "list.bullet");
  return (
    <Sheet
      title={words(
        language,
        collection ? "Edit collection" : "New collection",
        collection ? "Editar colección" : "Nueva colección",
      )}
      close={close}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (title.trim())
            save({
              ...collection,
              id: collection?.id || uid(),
              title: userText(title.trim()),
              symbol: symbol.trim() || "list.bullet",
              fields: collection?.fields || [],
              createdAt: collection?.createdAt || now(),
            });
        }}
      >
        <label>
          {words(language, "Name", "Nombre")}
          <input
            autoFocus
            required
            maxLength={240}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder={words(
              language,
              "What are you collecting?",
              "¿Qué estás coleccionando?",
            )}
          />
        </label>
        <label>
          {words(language, "Icon or emoji", "Icono o emoji")}
          <div className="input-with-icon">
            <Symbol name={symbol} />
            <input
              value={symbol}
              maxLength={40}
              onChange={(e) => setSymbol(e.target.value)}
            />
          </div>
        </label>
        <p className="muted">
          {words(
            language,
            "Start with a list. Ask Blue to add the information and indicators you need.",
            "Empieza con una lista. Pide a Blue la información y los indicadores que necesites.",
          )}
        </p>
        <button className="primary" type="submit">
          <Plus size={18} />
          {words(language, "Save collection", "Guardar colección")}
        </button>
      </form>
    </Sheet>
  );
}
export function NoteEditor({
  note,
  language,
  save,
  close,
}: {
  note?: Note;
  language: Language;
  save: (n: Note) => void;
  close: () => void;
}) {
  const key = `blue.draft.note.${note?.id || "new"}.${note?.revision ?? 0}`;
  const [title, setTitle, clearTitle] = useDraft(
    key + ".title",
    note ? text(note.title, language) : "",
  );
  const [body, setBody, clearBody] = useDraft(
    key + ".body",
    note ? text(note.markdown, language) : "",
  );
  return (
    <Sheet
      title={words(
        language,
        note ? "Edit note" : "New note",
        note ? "Editar nota" : "Nueva nota",
      )}
      close={close}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          save({
            ...note,
            id: note?.id || uid(),
            title: userText(title.trim()),
            markdown: userText(body),
            updatedAt: now(),
            revision: (note?.revision ?? -1) + 1,
          });
          clearTitle();
          clearBody();
        }}
      >
        <label>
          {words(language, "Title", "Título")}
          <input
            autoFocus
            required
            value={title}
            maxLength={240}
            onChange={(e) => setTitle(e.target.value)}
          />
        </label>
        <label>
          {words(language, "Your note · Markdown", "Tu nota · Markdown")}
          <textarea
            className="markdown-editor"
            value={body}
            maxLength={20000}
            onChange={(e) => setBody(e.target.value)}
            placeholder="# …"
          />
        </label>
        <button className="primary" type="submit">
          <Save size={18} />
          {words(language, "Save note", "Guardar nota")}
        </button>
      </form>
    </Sheet>
  );
}
export function ItemEditor({
  item,
  collection,
  language,
  save,
  close,
}: {
  item?: Item;
  collection: Collection;
  language: Language;
  save: (r: Item) => void;
  close: () => void;
}) {
  const key = `blue.draft.item.${collection.id}.${item?.id || "new"}.${item?.revision ?? 0}`;
  const [title, setTitle, clearTitle] = useDraft(
    key + ".title",
    item?.title || "",
  );
  const [body, setBody, clearBody] = useDraft(
    key + ".body",
    item ? text(item.markdown, language) : "",
  );
  const [values, setValues, clearValues] = useDraft<Record<string, Value>>(
    key + ".values",
    item?.values || {},
  );
  const [star, setStar, clearStar] = useDraft(
    key + ".star",
    item ? favorite(item) : false,
  );
  const set = (id: string, v: Value | undefined) =>
    setValues((old) => {
      const n = { ...old };
      if (v) n[id] = v;
      else delete n[id];
      return n;
    });
  const flags = collection.fields.filter(
    (f) => boolean(f) && f.kind !== "favorite",
  );
  return (
    <Sheet
      title={words(
        language,
        item ? "Edit item" : "New item",
        item ? "Editar elemento" : "Nuevo elemento",
      )}
      close={close}
    >
      <form
        onSubmit={(e: FormEvent) => {
          e.preventDefault();
          save({
            ...item,
            id: item?.id || uid(),
            collectionID: collection.id,
            title: title.trim(),
            markdown: userText(body),
            values,
            favorite: star,
            revision: (item?.revision ?? -1) + 1,
            updatedAt: now(),
          });
          clearTitle();
          clearBody();
          clearValues();
          clearStar();
        }}
      >
        <label>
          {words(language, "Title", "Título")}
          <input
            autoFocus
            required
            value={title}
            maxLength={240}
            onChange={(e) => setTitle(e.target.value)}
          />
        </label>
        <div className="indicator-meanings">
          <div>
            <Indicator
              field={favoriteField}
              active={star}
              onClick={() => setStar(!star)}
              language={language}
            />
            <span>{text(favoriteField.label, language)}</span>
          </div>
          {flags.map((f) => (
            <div key={f.id}>
              <Indicator
                field={f}
                active={values[f.id]?.flag?._0 || false}
                onClick={() =>
                  set(f.id, { flag: { _0: !values[f.id]?.flag?._0 } })
                }
                language={language}
              />
              <span>{text(f.label, language)}</span>
            </div>
          ))}
        </div>
        {collection.fields
          .filter((f) => !boolean(f))
          .map((f) => (
            <label key={f.id}>
              {text(f.label, language)}
              {f.kind === "status" ? (
                <div className="choice-row">
                  {f.options.map((o) => (
                    <button
                      type="button"
                      key={o.id}
                      className={`choice ${values[f.id]?.option?._0 === o.id ? "selected" : ""}`}
                      aria-pressed={values[f.id]?.option?._0 === o.id}
                      onClick={() =>
                        set(
                          f.id,
                          values[f.id]?.option?._0 === o.id
                            ? undefined
                            : { option: { _0: o.id } },
                        )
                      }
                    >
                      {text(o.label, language)}
                    </button>
                  ))}
                </div>
              ) : (
                <input
                  value={
                    f.kind === "date"
                      ? values[f.id]?.date
                        ? new Date((values[f.id].date!._0 + 978307200) * 1000)
                            .toISOString()
                            .slice(0, 10)
                        : ""
                      : String(value(values[f.id]))
                  }
                  type={
                    ["number", "rating"].includes(f.kind)
                      ? "number"
                      : f.kind === "date"
                        ? "date"
                        : "text"
                  }
                  step="any"
                  min={f.kind === "rating" ? 0 : undefined}
                  max={f.kind === "rating" ? 10 : undefined}
                  maxLength={2000}
                  onChange={(e) => {
                    const v = e.target.value;
                    if (!v) {
                      set(f.id, undefined);
                      return;
                    }
                    set(
                      f.id,
                      ["number", "rating"].includes(f.kind)
                        ? { number: { _0: Number(v) } }
                        : f.kind === "tags"
                          ? {
                              tags: {
                                _0: v
                                  .split(",")
                                  .map((x) => x.trim())
                                  .filter(Boolean),
                              },
                            }
                          : f.kind === "date"
                            ? {
                                date: {
                                  _0:
                                    new Date(v + "T12:00:00Z").getTime() /
                                      1000 -
                                    978307200,
                                },
                              }
                            : { text: { _0: v } },
                    );
                  }}
                />
              )}
            </label>
          ))}
        <label>
          {words(language, "Notes · Markdown", "Notas · Markdown")}
          <textarea
            value={body}
            maxLength={20000}
            onChange={(e) => setBody(e.target.value)}
          />
        </label>
        <button className="primary" type="submit">
          <Save size={18} />
          {words(language, "Save item", "Guardar elemento")}
        </button>
      </form>
    </Sheet>
  );
}
export function IndicatorEditor({
  language,
  save,
  close,
}: {
  language: Language;
  save: (f: Field) => void;
  close: () => void;
}) {
  const [name, setName] = useState("");
  const [icon, setIcon] = useState("🗿");
  const [tint, setTint] = useState("purple");
  return (
    <Sheet
      title={words(language, "New indicator", "Nuevo indicador")}
      close={close}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          save({
            id: "flag-" + uid().slice(0, 8).toLowerCase(),
            label: userText(name.trim()),
            kind: "checkbox",
            icon: icon.trim(),
            tint,
            options: [],
            showInRow: true,
          });
        }}
      >
        <label>
          {words(language, "Meaning", "Significado")}
          <input
            required
            autoFocus
            value={name}
            maxLength={80}
            placeholder="Bass"
            onChange={(e) => setName(e.target.value)}
          />
        </label>
        <label>
          {words(language, "Emoji or icon", "Emoji o icono")}
          <input
            required
            value={icon}
            maxLength={40}
            onChange={(e) => setIcon(e.target.value)}
          />
        </label>
        <div className="swatches">
          {colors.map((c) => (
            <button
              type="button"
              key={c}
              style={{ background: `var(--${c})` }}
              className={c === tint ? "selected" : ""}
              aria-label={c}
              aria-pressed={c === tint}
              onClick={() => setTint(c)}
            >
              {c === tint ? "✓" : ""}
            </button>
          ))}
        </div>
        <div className="indicator-preview">
          <Indicator
            field={{
              id: "preview",
              label: userText(name || "Bass"),
              kind: "checkbox",
              options: [],
              showInRow: true,
              icon,
              tint,
            }}
            active={false}
            onClick={() => {}}
            language={language}
          />
          <span>→</span>
          <Indicator
            field={{
              id: "preview",
              label: userText(name || "Bass"),
              kind: "checkbox",
              options: [],
              showInRow: true,
              icon,
              tint,
            }}
            active
            onClick={() => {}}
            language={language}
          />
        </div>
        <button className="primary" type="submit">
          <Plus size={18} />
          {words(language, "Add indicator", "Añadir indicador")}
        </button>
      </form>
    </Sheet>
  );
}
