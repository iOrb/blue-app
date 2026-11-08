"use client";
import { useState } from "react";
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
import { Sheet, words, useDraft } from "./blue-editors";
import { Symbol } from "./blue-icons";

export function BlueCalendar({
  library,
  language,
  save,
  remove,
  openItem,
}: {
  library: Library;
  language: Language;
  save: (event: CalendarEvent) => boolean;
  remove: (event: CalendarEvent) => void;
  openItem: (id: string) => void;
}) {
  const [day, setDay] = useState(() => dateKey(new Date()));
  const [month, setMonth] = useState(() => new Date());
  const [editing, setEditing] = useState<{ event?: CalendarEvent }>();
  const t = (en: string, es: string) => words(language, en, es);
  const days = monthDays(month, language);
  const today = dateKey(new Date());
  const entries = agenda(library, day, language);
  return (
    <section className="calendar" aria-label={t("Calendar", "Calendario")}>
      <div className="calendar-heading">
        <h1>
          {month.toLocaleDateString(language, {
            month: "long",
            year: "numeric",
          })}
        </h1>
        <button
          className="text-button"
          onClick={() => {
            setDay(today);
            setMonth(new Date());
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
          <ChevronLeft size={20} />
        </button>
        <button
          className="icon-button"
          aria-label={t("Next month", "Mes siguiente")}
          onClick={() =>
            setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1, 12))
          }
        >
          <ChevronRight size={20} />
        </button>
      </div>
      <div className="calendar-grid">
        {days.slice(0, 7).map((date) => (
          <span className="weekday" key={dateKey(date)}>
            {date.toLocaleDateString(language, { weekday: "narrow" })}
          </span>
        ))}
        {days.map((date) => {
          const key = dateKey(date),
            count = agenda(library, key, language).length;
          return (
            <button
              key={key}
              className={`calendar-day ${day === key ? "selected" : ""} ${today === key ? "today" : ""} ${date.getMonth() !== month.getMonth() ? "outside-month" : ""}`}
              aria-label={`${date.toLocaleDateString(language, { dateStyle: "full" })}${count ? ` · ${count}` : ""}`}
              aria-pressed={day === key}
              onClick={() => {
                setDay(key);
                if (date.getMonth() !== month.getMonth()) setMonth(date);
              }}
            >
              <span>{date.getDate()}</span>
              <i className={count ? "has-events" : ""} />
            </button>
          );
        })}
      </div>
      <div className="section-label agenda-heading">
        <h2>
          {dateFromKey(day).toLocaleDateString(language, {
            weekday: "long",
            day: "numeric",
            month: "short",
          })}
        </h2>
        <button
          className="icon-button selected"
          aria-label={t("New event", "Nuevo evento")}
          onClick={() => setEditing({})}
        >
          <Plus size={22} />
        </button>
      </div>
      <div className="agenda-list">
        {entries.map((entry) => (
          <button
            className="agenda-entry"
            key={entry.id}
            onClick={() =>
              entry.recordID
                ? openItem(entry.recordID)
                : setEditing({
                    event: library.events!.find((e) => e.id === entry.eventID),
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
            <span>
              <strong>{entry.title}</strong>
              {entry.detail && <small>{entry.detail}</small>}
            </span>
            <ChevronRight size={17} />
          </button>
        ))}
        {!entries.length && (
          <div className="calendar-empty">
            <CalendarDays size={25} />
            <span>{t("Nothing planned", "Sin planes")}</span>
          </div>
        )}
      </div>
      {editing && (
        <EventEditor
          key={`${editing.event?.id || day}:${editing.event?.revision || 0}`}
          event={editing.event}
          day={day}
          language={language}
          close={() => setEditing(undefined)}
          save={(event) => {
            if (save(event)) {
              setDay(
                event.allDay
                  ? event.day!
                  : dateKey(new Date((event.date + 978307200) * 1000)),
              );
              setMonth(dateFromKey(event.day!));
              setEditing(undefined);
              return true;
            }
            return false;
          }}
          remove={(event) => {
            remove(event);
            setEditing(undefined);
          }}
        />
      )}
    </section>
  );
}
function EventEditor({
  event,
  day,
  language,
  close,
  save,
  remove,
}: {
  event?: CalendarEvent;
  day: string;
  language: Language;
  close: () => void;
  save: (e: CalendarEvent) => boolean;
  remove: (e: CalendarEvent) => void;
}) {
  const t = (en: string, es: string) => words(language, en, es);
  const date = event ? new Date((event.date + 978307200) * 1000) : new Date();
  const [draft, setDraft, clear] = useDraft(
    `blue.draft.event.${event?.id || day}.${event?.revision || 0}`,
    {
      title: event?.title || "",
      day: event?.day || (event ? dateKey(date) : day),
      time: event
        ? `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`
        : "09:00",
      allDay: event?.allDay || false,
      color: event?.color || "blue",
    },
  );
  const [error, setError] = useState("");
  return (
    <Sheet
      title={t(
        event ? "Edit event" : "New event",
        event ? "Editar evento" : "Nuevo evento",
      )}
      close={close}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          const date = new Date(
            `${draft.day}T${draft.allDay ? "12:00" : draft.time}:00`,
          );
          if (!Number.isFinite(date.getTime()) || dateKey(date) !== draft.day) {
            setError(t("Check the date", "Revisa la fecha"));
            return;
          }
          if (
            save({
              id: event?.id || uid(),
              title: draft.title.trim(),
              date: date.getTime() / 1000 - 978307200,
              day: draft.day,
              allDay: draft.allDay,
              color: draft.color,
              revision: event ? event.revision + 1 : 0,
            })
          )
            clear();
        }}
      >
        <input
          autoFocus
          required
          maxLength={240}
          aria-label={t("Event title", "Título del evento")}
          placeholder={t("What’s the plan?", "¿Qué plan tienes?")}
          value={draft.title}
          onChange={(e) => setDraft({ ...draft, title: e.target.value })}
        />
        <label>
          {t("Date", "Fecha")}
          <input
            type="date"
            required
            value={draft.day}
            onInput={(e) => {
              const value = e.currentTarget.value;
              setDraft((d) => ({ ...d, day: value }));
            }}
          />
        </label>
        <div className="event-time-row">
          <button
            type="button"
            className={`choice ${draft.allDay ? "selected" : ""}`}
            aria-pressed={draft.allDay}
            onClick={() => setDraft({ ...draft, allDay: !draft.allDay })}
          >
            <Check size={17} />
            {t("All day", "Todo el día")}
          </button>
          {!draft.allDay && (
            <input
              type="time"
              required
              aria-label={t("Time", "Hora")}
              value={draft.time}
              onInput={(e) => {
                const value = e.currentTarget.value;
                setDraft((d) => ({ ...d, time: value }));
              }}
            />
          )}
        </div>
        <div className="swatches" aria-label={t("Color", "Color")}>
          {colors.map((color) => (
            <button
              type="button"
              key={color}
              aria-label={t("Color", "Color") + ": " + color}
              aria-pressed={draft.color === color}
              style={{ background: `var(--${color})` }}
              className={draft.color === color ? "selected" : ""}
              onClick={() => setDraft({ ...draft, color })}
            >
              {draft.color === color && <Check size={17} />}
            </button>
          ))}
        </div>
        <small>
          {t(
            "Saved in your calendar. No alarm.",
            "Se guarda en el calendario. Sin alarma.",
          )}
        </small>
        {error && <p role="alert">{error}</p>}
        <button className="primary" disabled={!draft.title.trim()}>
          {t("Save", "Guardar")}
        </button>
        {event && (
          <button
            type="button"
            className="icon-button danger"
            aria-label={t("Delete event", "Eliminar evento")}
            onClick={() => {
              clear();
              remove(event);
            }}
          >
            <Trash2 size={20} />
          </button>
        )}
      </form>
    </Sheet>
  );
}
