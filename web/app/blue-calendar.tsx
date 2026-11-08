"use client";
import { useRef, useState } from "react";
import {
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  Plus,
  Trash2,
  Check,
} from "lucide-react";
import {
  type CalendarEvent,
  type Library,
  type Language,
  colors,
  uid,
} from "./blue-model";
import { agenda, dateKey, dateFromKey, monthDays } from "./blue-calendar-model";
import { Sheet, Confirm, words } from "./blue-ui";
import { Symbol } from "./blue-icons";
export function BlueCalendar({
  library,
  language,
  save,
  remove,
  openItem,
  onSelectDay,
}: {
  library: Library;
  language: Language;
  save: (e: CalendarEvent) => boolean;
  remove: (e: CalendarEvent) => void;
  openItem: (id: string) => void;
  onSelectDay?: (day: string) => void;
}) {
  const [month, setMonth] = useState(() => new Date()),
    [day, setDay] = useState<string>(),
    [editing, setEditing] = useState<{ event?: CalendarEvent; day: string }>();
  const t = (en: string, es: string) => words(language, en, es),
    days = monthDays(month, language),
    today = dateKey(new Date());
  const select = (d: string) => {
    setDay(d);
    onSelectDay?.(d);
  };
  return (
    <section className="calendar" aria-label={t("Calendar", "Calendario")}>
      <div className="calendar-heading">
        <h2>
          {month.toLocaleDateString(language, {
            month: "long",
            year: "numeric",
          })}
        </h2>
        <button
          className="plain"
          onClick={() => {
            setMonth(new Date());
            select(today);
          }}
        >
          {t("Today", "Hoy")}
        </button>
        <button
          className="icon-button"
          aria-label={t("Previous month", "Mes anterior")}
          onClick={() =>
            setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1, 12))
          }
        >
          <ChevronLeft size={19} />
        </button>
        <button
          className="icon-button"
          aria-label={t("Next month", "Mes siguiente")}
          onClick={() =>
            setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1, 12))
          }
        >
          <ChevronRight size={19} />
        </button>
      </div>
      <div className="calendar-grid">
        {days.slice(0, 7).map((d) => (
          <span className="weekday" key={dateKey(d)}>
            {d.toLocaleDateString(language, { weekday: "narrow" })}
          </span>
        ))}
        {days.map((date) => {
          const key = dateKey(date),
            count = agenda(library, key, language).length;
          return (
            <button
              key={key}
              className={`calendar-day ${key === today ? "today" : ""} ${date.getMonth() !== month.getMonth() ? "outside-month" : ""}`}
              aria-label={
                date.toLocaleDateString(language, { dateStyle: "full" }) +
                (count ? ` · ${count}` : "")
              }
              onClick={() => select(key)}
            >
              <span>{date.getDate()}</span>
              <i className={count ? "has-events" : ""} />
            </button>
          );
        })}
      </div>
      {day && (
        <Sheet
          title={dateFromKey(day).toLocaleDateString(language, {
            weekday: "long",
            day: "numeric",
            month: "long",
          })}
          close={() => setDay(undefined)}
        >
          <div className="agenda-top">
            <button
              className="round-dark"
              aria-label={t("New event", "Nuevo evento")}
              onClick={() => setEditing({ day })}
            >
              <Plus size={21} />
            </button>
          </div>
          {agenda(library, day, language).map((entry) => (
            <button
              className="agenda-entry"
              key={entry.id}
              onClick={() =>
                entry.recordID
                  ? openItem(entry.recordID)
                  : setEditing({
                      day,
                      event: library.events?.find(
                        (e) => e.id === entry.eventID,
                      ),
                    })
              }
            >
              <span
                className="agenda-dot"
                style={{ background: `var(--${entry.color})` }}
              />
              {entry.symbol ? (
                <Symbol name={entry.symbol} size={19} />
              ) : (
                <span className="agenda-time">
                  {entry.allDay
                    ? t("All day", "Todo el día")
                    : new Date(
                        (entry.date + 978307200) * 1000,
                      ).toLocaleTimeString(language, {
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                </span>
              )}
              <strong>{entry.title}</strong>
              <ChevronRight size={16} />
            </button>
          ))}
          {!agenda(library, day, language).length && (
            <div className="calendar-empty">
              <CalendarDays size={24} />
              <span>{t("Nothing planned", "Sin planes")}</span>
            </div>
          )}
        </Sheet>
      )}
      {editing && (
        <EventEditor
          key={editing.event?.id || editing.day}
          event={editing.event}
          day={editing.day}
          language={language}
          save={save}
          remove={remove}
          close={() => setEditing(undefined)}
        />
      )}
    </section>
  );
}
export function EventEditor({
  event,
  day,
  language,
  save,
  remove,
  close,
}: {
  event?: CalendarEvent;
  day: string;
  language: Language;
  save: (e: CalendarEvent) => boolean;
  remove: (e: CalendarEvent) => void;
  close: () => void;
}) {
  const date = event ? new Date((event.date + 978307200) * 1000) : new Date();
  const [draft, setDraft] = useState({
    title: event?.title || "",
    day: event?.day || (event ? dateKey(date) : day),
    time: event
      ? `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`
      : "09:00",
    allDay: event?.allDay || false,
    color: event?.color || "blue",
  });
  const saved = useRef(event),
    identity = useRef(event?.id || uid()),
    [error, setError] = useState(""),
    [deleting, setDeleting] = useState(false);
  const t = (en: string, es: string) => words(language, en, es);
  const update = (patch: Partial<typeof draft>) => {
    const next = { ...draft, ...patch };
    setDraft(next);
    if (!next.title.trim() || !next.day || !next.time) return;
    const date = new Date(
      `${next.day}T${next.allDay ? "12:00" : next.time}:00`,
    );
    if (!Number.isFinite(date.getTime())) return;
    const e: CalendarEvent = {
      id: identity.current,
      title: next.title.trim(),
      date: date.getTime() / 1000 - 978307200,
      day: next.day,
      allDay: next.allDay,
      color: next.color,
      revision: saved.current ? saved.current.revision + 1 : 0,
    };
    if (save(e)) {
      saved.current = e;
      setError("");
    } else
      setError(
        t(
          "Could not save. Keep this open and try again.",
          "No se pudo guardar. Mantén abierto y vuelve a intentarlo.",
        ),
      );
  };
  return (
    <>
      <Sheet
        title={t("Event", "Evento")}
        close={close}
        heading={
          <input
            className="inline-title"
            autoFocus
            aria-label={t("Event title", "Título del evento")}
            placeholder={t("What’s the plan?", "¿Qué plan tienes?")}
            maxLength={240}
            value={draft.title}
            onChange={(e) => update({ title: e.target.value })}
          />
        }
      >
        {" "}
        <div className="event-dates">
          <input
            type="date"
            aria-label={t("Date", "Fecha")}
            value={draft.day}
            onInput={(e) => update({ day: e.currentTarget.value })}
          />
          {!draft.allDay && (
            <input
              type="time"
              aria-label={t("Time", "Hora")}
              value={draft.time}
              onInput={(e) => update({ time: e.currentTarget.value })}
            />
          )}
          <button
            className={`property-icon ${draft.allDay ? "active" : ""}`}
            title={t("All day", "Todo el día")}
            aria-label={t("All day", "Todo el día")}
            aria-pressed={draft.allDay}
            onClick={() => update({ allDay: !draft.allDay })}
          >
            <CalendarDays size={21} />
          </button>
        </div>
        <div className="swatches">
          {colors.map((color) => (
            <button
              key={color}
              aria-label={color}
              aria-pressed={draft.color === color}
              style={{ background: `var(--${color})` }}
              onClick={() => update({ color })}
            >
              {draft.color === color && <Check size={16} />}
            </button>
          ))}
        </div>
        <small className="muted">
          {t("Calendar only · no alarm", "Solo calendario · sin alarma")}
        </small>
        {error && <p role="alert">{error}</p>}
        {saved.current && (
          <button
            className="icon-button danger"
            aria-label={t("Delete event", "Eliminar evento")}
            onClick={() => setDeleting(true)}
          >
            <Trash2 size={20} />
          </button>
        )}
      </Sheet>
      {deleting && (
        <Confirm
          language={language}
          title={saved.current?.title || draft.title}
          cancel={() => setDeleting(false)}
          confirm={() => {
            if (saved.current) remove(saved.current);
            close();
          }}
        />
      )}
    </>
  );
}
