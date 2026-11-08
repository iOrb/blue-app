"use client";
import { useEffect, useRef, useState, type ReactNode } from "react";
import Markdown from "react-markdown";
import remarkGfm from "remark-gfm";
import {
  Star,
  Heart,
  Eye,
  Check,
  Circle,
  Play,
  CalendarDays,
  Hash,
  Type,
  Tag,
  Minus,
} from "lucide-react";
import {
  type Field,
  type Value,
  type Language,
  text,
  value,
  colors,
  safeLink,
} from "./blue-model";
import { Symbol } from "./blue-icons";
export const words = (language: Language, en: string, es: string) =>
  language === "es" ? es : en;
export function Sheet({
  title,
  children,
  close,
  footer,
  heading,
}: {
  title: string;
  heading?: ReactNode;
  children: ReactNode;
  close: () => void;
  footer?: ReactNode;
}) {
  const panel = useRef<HTMLElement>(null),
    scroll = useRef<HTMLDivElement>(null),
    start = useRef<{ y: number; allowed: boolean } | undefined>(undefined);
  const [offset, setOffset] = useState(0);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    if (!panel.current?.contains(document.activeElement))
      panel.current?.focus();
    return () => {
      document.body.style.overflow = overflow;
      previous?.focus();
    };
  }, []);
  return (
    <div
      className="sheet-shade"
      onClick={(e) => {
        if (e.target === e.currentTarget) close();
      }}
    >
      <section
        className="sheet"
        role="dialog"
        aria-modal="false"
        aria-label={title}
        tabIndex={-1}
        ref={panel}
        style={{ transform: `translateY(${offset}px)` }}
        onTouchStart={(e) => {
          start.current = {
            y: e.touches[0].clientY,
            allowed:
              (scroll.current?.scrollTop || 0) <= 0 &&
              !(e.target as HTMLElement).closest(
                "input, textarea, .number-wheel",
              ),
          };
        }}
        onTouchMove={(e) => {
          if (start.current?.allowed)
            setOffset(Math.max(0, e.touches[0].clientY - start.current.y));
        }}
        onTouchEnd={() => {
          if (offset > 90) close();
          setOffset(0);
          start.current = undefined;
        }}
        onKeyDown={(e) => {
          if (e.key === "Escape") {
            e.preventDefault();
            e.stopPropagation();
            close();
          }
          if (e.key === "Tab") {
            const nodes = [
              ...(panel.current?.querySelectorAll<HTMLElement>(
                'button:not([disabled]), input, textarea, a[href], [tabindex="0"]',
              ) || []),
              ...document.querySelectorAll<HTMLElement>(".floating-nav button"),
            ];
            if (nodes?.length) {
              const first = nodes[0],
                last = nodes[nodes.length - 1];
              if (
                e.shiftKey &&
                (document.activeElement === first ||
                  document.activeElement === panel.current)
              ) {
                e.preventDefault();
                last.focus();
              } else if (!e.shiftKey && document.activeElement === last) {
                e.preventDefault();
                first.focus();
              }
            }
          }
        }}
      >
        <header
          className="sheet-heading"
          onPointerDown={(e) => {
            if (
              e.pointerType === "mouse" &&
              !(e.target as HTMLElement).closest("input,button")
            ) {
              start.current = { y: e.clientY, allowed: true };
              e.currentTarget.setPointerCapture(e.pointerId);
            }
          }}
          onPointerMove={(e) => {
            if (e.pointerType === "mouse" && start.current?.allowed)
              setOffset(Math.max(0, e.clientY - start.current.y));
          }}
          onPointerUp={() => {
            if (offset > 90) close();
            setOffset(0);
            start.current = undefined;
          }}
        >
          <div className="sheet-grip" />
          {heading || <h2>{title}</h2>}
        </header>
        <div className="sheet-body" ref={scroll}>
          {children}
        </div>
        {footer && <div className="sheet-footer">{footer}</div>}
      </section>
    </div>
  );
}
export function Confirm({
  language,
  title,
  confirm,
  cancel,
}: {
  language: Language;
  title: string;
  confirm: () => void;
  cancel: () => void;
}) {
  return (
    <Sheet title={words(language, "Delete?", "¿Eliminar?")} close={cancel}>
      <p className="confirmation-copy">{title}</p>
      <div className="confirmation-actions">
        <button className="plain" onClick={cancel}>
          {words(language, "Keep", "Conservar")}
        </button>
        <button className="danger-button" onClick={confirm}>
          {words(language, "Delete", "Eliminar")}
        </button>
      </div>
    </Sheet>
  );
}
export function EditableText({
  value: original,
  save,
  label,
  large = false,
  placeholder = "",
}: {
  value: string;
  save: (s: string) => void;
  label: string;
  large?: boolean;
  placeholder?: string;
}) {
  const [draft, setDraft] = useState(original);
  const focused = useRef(false);
  useEffect(() => {
    if (!focused.current) setDraft(original);
  }, [original]);
  return (
    <input
      className={large ? "inline-title" : "inline-text"}
      value={draft}
      maxLength={240}
      aria-label={label}
      placeholder={placeholder}
      onFocus={() => {
        focused.current = true;
      }}
      onBlur={() => {
        focused.current = false;
        if (!draft.trim()) setDraft(original);
      }}
      onChange={(e) => {
        setDraft(e.target.value);
        if (e.target.value.trim()) save(e.target.value);
      }}
    />
  );
}
export function MarkdownBody({
  value: body,
  save,
  language,
  readOnly = false,
}: {
  value: string;
  save: (s: string) => void;
  language: Language;
  readOnly?: boolean;
}) {
  const [editing, setEditing] = useState(false),
    [draft, setDraft] = useState(body);
  useEffect(() => {
    if (!editing) setDraft(body);
  }, [body, editing]);
  return editing ? (
    <textarea
      className="markdown-editor"
      autoFocus
      aria-label={words(language, "Markdown", "Markdown")}
      value={draft}
      maxLength={20000}
      onChange={(e) => {
        setDraft(e.target.value);
        save(e.target.value);
      }}
      onBlur={() => {
        if (draft === body) setEditing(false);
      }}
    />
  ) : (
    <div
      className="markdown tap-to-write"
      role={readOnly ? undefined : "button"}
      tabIndex={readOnly ? undefined : 0}
      aria-label={
        readOnly
          ? undefined
          : words(language, "Write in this note", "Escribir en esta nota")
      }
      onClick={(e) => {
        if (!readOnly && !(e.target as HTMLElement).closest("a"))
          setEditing(true);
      }}
      onKeyDown={(e) => {
        if (!readOnly && e.key === "Enter") {
          e.preventDefault();
          setEditing(true);
        }
      }}
    >
      {body ? (
        <Markdown
          remarkPlugins={[remarkGfm]}
          components={{
            a: ({ href, children }) => (
              <a
                href={href && safeLink(href)}
                target="_blank"
                rel="noopener noreferrer"
                onClick={(e) => e.stopPropagation()}
              >
                {children}
              </a>
            ),
          }}
        >
          {body}
        </Markdown>
      ) : (
        <span className="muted">{words(language, "Write…", "Escribe…")}</span>
      )}
    </div>
  );
}
const legacyOptions: Record<string, { icon: string; inactive?: boolean }> = {
  wantWatch: { icon: "eye", inactive: true },
  watched: { icon: "eye" },
  watching: { icon: "play" },
  finished: { icon: "checkmark" },
  wantPlay: { icon: "gamecontroller", inactive: true },
  playing: { icon: "gamecontroller" },
  wantTry: { icon: "fork.knife", inactive: true },
  tried: { icon: "checkmark" },
  wantVisit: { icon: "mappin", inactive: true },
  visited: { icon: "mappin" },
  wantExplore: { icon: "music.note", inactive: true },
  exploring: { icon: "music.note" },
};
export const inactiveOption = (f: Field) =>
  f.inactiveOptionID ||
  f.options.find((o) => legacyOptions[o.id]?.inactive)?.id;
export const optionIcon = (f: Field, id: string) =>
  f.options.find((o) => o.id === id)?.icon ||
  legacyOptions[id]?.icon ||
  f.icon ||
  "checkmark.circle";
export function FieldControl({
  field,
  stored,
  language,
  save,
  filter = false,
}: {
  field: Field;
  stored?: Value;
  language: Language;
  save: (v: Value | undefined) => void;
  filter?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const label = text(field.label, language),
    raw = value(stored);
  const color = colors.includes(field.tint || "")
    ? field.tint
    : field.kind === "favorite"
      ? "yellow"
      : field.kind === "like"
        ? "pink"
        : "blue";
  const style = { "--indicator": `var(--${color})` } as React.CSSProperties;
  if (["checkbox", "favorite", "like"].includes(field.kind))
    return (
      <button
        className={`property-icon ${stored?.flag?._0 ? "active" : ""}`}
        style={style}
        aria-label={label}
        title={label}
        aria-pressed={!!stored?.flag?._0}
        onClick={() => save({ flag: { _0: !stored?.flag?._0 } })}
      >
        <Symbol
          name={
            field.icon ||
            (field.kind === "favorite"
              ? "star"
              : field.kind === "like"
                ? "heart"
                : "checkmark.circle")
          }
          size={21}
        />
      </button>
    );
  if (field.kind === "status")
    return (
      <span className="status-icons">
        {field.options
          .filter((o) => o.id !== inactiveOption(field))
          .map((option) => (
            <button
              key={option.id}
              className={`property-icon ${raw === option.id ? "active" : ""}`}
              style={style}
              aria-label={text(option.label, language)}
              title={text(option.label, language)}
              aria-pressed={raw === option.id}
              onClick={() =>
                save(
                  raw === option.id
                    ? filter
                      ? undefined
                      : inactiveOption(field)
                        ? { option: { _0: inactiveOption(field)! } }
                        : undefined
                    : { option: { _0: option.id } },
                )
              }
            >
              <Symbol name={optionIcon(field, option.id)} size={21} />
            </button>
          ))}
      </span>
    );
  const numeric = field.kind === "rating" || field.kind === "number";
  const Icon =
    field.kind === "date" ? CalendarDays : field.kind === "tags" ? Tag : Type;
  return (
    <>
      <button
        className={numeric ? "number-value" : "property-value"}
        aria-label={`${label}: ${raw === "" ? "—" : raw}`}
        title={label}
        onClick={() => setOpen(true)}
      >
        {numeric ? (
          raw === "" ? (
            <Minus size={18} />
          ) : (
            new Intl.NumberFormat(language, {
              maximumFractionDigits: 4,
            }).format(Number(raw))
          )
        ) : (
          <>
            <Icon size={17} />
            <span>
              {field.kind === "date" && stored?.date
                ? new Date(
                    (stored.date._0 + 978307200) * 1000,
                  ).toLocaleDateString(language)
                : String(raw) || label}
            </span>
          </>
        )}
      </button>
      {open && (
        <Sheet title={label} close={() => setOpen(false)}>
          {numeric ? (
            <NumberWheel
              field={field}
              stored={stored}
              language={language}
              save={save}
            />
          ) : field.kind === "date" ? (
            <input
              type="date"
              aria-label={label}
              value={
                stored?.date
                  ? new Date(
                      (stored.date._0 + 978307200) * 1000,
                    ).toLocaleDateString("sv-SE")
                  : ""
              }
              onInput={(e) => {
                if (e.currentTarget.value)
                  save({
                    date: {
                      _0:
                        new Date(
                          e.currentTarget.value + "T12:00:00",
                        ).getTime() /
                          1000 -
                        978307200,
                    },
                  });
              }}
            />
          ) : (
            <ValueDraft
              aria-label={label}
              value={String(raw)}
              save={(draft) =>
                save(
                  draft
                    ? field.kind === "tags"
                      ? {
                          tags: {
                            _0: draft
                              .split(",")
                              .map((t) => t.trim())
                              .filter(Boolean),
                          },
                        }
                      : { text: { _0: draft } }
                    : undefined,
                )
              }
            />
          )}
        </Sheet>
      )}
    </>
  );
}
function NumberWheel({
  field,
  stored,
  language,
  save,
}: {
  field: Field;
  stored?: Value;
  language: Language;
  save: (v: Value | undefined) => void;
}) {
  const initial = stored?.number?._0,
    step = field.step || (field.kind === "rating" ? 0.5 : 1),
    minimum =
      field.minimum ??
      (field.kind === "rating"
        ? 0
        : Math.min(0, Math.floor((initial || 0) - 50))),
    maximum =
      field.maximum ??
      (field.kind === "rating"
        ? 10
        : Math.max(100, Math.ceil((initial || 0) + 50)));
  const numbers = Array.from(
    { length: Math.min(1001, Math.floor((maximum - minimum) / step) + 1) },
    (_, i) => Math.round((minimum + i * step) * 10000) / 10000,
  );
  if (initial !== undefined && !numbers.includes(initial))
    numbers.push(initial);
  numbers.sort((a, b) => a - b);
  const options: (number | undefined)[] = [undefined, ...numbers];
  const [index, setIndex] = useState(Math.max(0, options.indexOf(initial)));
  const scroller = useRef<HTMLDivElement>(null),
    timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined),
    last = useRef(initial),
    latest = useRef({ save, options }),
    pending = useRef<number | undefined>(undefined);
  latest.current = { save, options };
  useEffect(() => {
    if (scroller.current) scroller.current.scrollTop = index * 48;
    return () => {
      if (timer.current) clearTimeout(timer.current);
      if (pending.current !== undefined) {
        const n = latest.current.options[pending.current];
        if (n !== last.current)
          latest.current.save(
            n === undefined ? undefined : { number: { _0: n } },
          );
      }
    };
  }, []);
  const choose = (i: number) => {
    pending.current = undefined;
    setIndex(i);
    const n = options[i];
    if (n !== last.current) {
      last.current = n;
      save(n === undefined ? undefined : { number: { _0: n } });
    }
  };
  return (
    <div className="wheel-wrap">
      <div className="wheel-highlight" />
      <div
        className="number-wheel"
        ref={scroller}
        role="listbox"
        aria-label={text(field.label, language)}
        onScroll={() => {
          if (timer.current) clearTimeout(timer.current);
          pending.current = Math.max(
            0,
            Math.min(
              options.length - 1,
              Math.round((scroller.current?.scrollTop || 0) / 48),
            ),
          );
          timer.current = setTimeout(() => choose(pending.current!), 100);
        }}
      >
        {options.map((n, i) => (
          <button
            key={n ?? "empty"}
            role="option"
            aria-selected={i === index}
            className={i === index ? "selected" : ""}
            onClick={() => {
              choose(i);
              scroller.current?.scrollTo({
                top: i * 48,
                behavior: matchMedia("(prefers-reduced-motion: reduce)").matches
                  ? "instant"
                  : "smooth",
              });
            }}
          >
            {n === undefined
              ? "—"
              : new Intl.NumberFormat(language, {
                  maximumFractionDigits: 4,
                }).format(n)}
          </button>
        ))}
      </div>
    </div>
  );
}

function ValueDraft({
  value,
  save,
  ...props
}: {
  value: string;
  save: (value: string) => void;
  "aria-label": string;
}) {
  const [draft, setDraft] = useState(value);
  const focused = useRef(false);
  useEffect(() => {
    if (!focused.current) setDraft(value);
  }, [value]);
  return (
    <textarea
      {...props}
      className="plain-editor"
      autoFocus
      value={draft}
      onFocus={() => {
        focused.current = true;
      }}
      onBlur={() => {
        focused.current = false;
      }}
      onChange={(e) => {
        setDraft(e.target.value);
        save(e.target.value);
      }}
    />
  );
}
