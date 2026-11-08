import {
  Star,
  Heart,
  Check,
  List,
  FileText,
  Film,
  Music2,
  BookOpen,
  Gamepad2,
  MapPin,
  Coffee,
  Tv,
  Eye,
  Play,
  Utensils,
  Wine,
  Circle,
  Cigarette,
  Headphones,
  SlidersHorizontal,
  type LucideIcon,
} from "lucide-react";
import type { CSSProperties } from "react";
import { type Field, type Language, text, colors } from "./blue-model";
const symbols: Record<string, LucideIcon> = {
  star: Star,
  "star.fill": Star,
  heart: Heart,
  "heart.fill": Heart,
  checkmark: Check,
  "checkmark.circle": Check,
  "checkmark.circle.fill": Check,
  "list.bullet": List,
  "list.bullet.rectangle": List,
  "doc.text": FileText,
  eye: Eye,
  play: Play,
  tv: Tv,
  "tv.fill": Tv,
  "fork.knife": Utensils,
  wineglass: Wine,
  film: Film,
  "film.fill": Film,
  popcorn: Film,
  "music.note": Music2,
  headphones: Headphones,
  book: BookOpen,
  "book.closed": BookOpen,
  gamecontroller: Gamepad2,
  mappin: MapPin,
  "cup.and.saucer": Coffee,
  smoke: Cigarette,
  "slider.horizontal.3": SlidersHorizontal,
};
export function Symbol({
  name = "list.bullet",
  size = 22,
}: {
  name?: string;
  size?: number;
}) {
  const Icon = symbols[name];
  return Icon ? (
    <Icon size={size} aria-hidden />
  ) : /[^\x00-\x7F]/u.test(name) ? (
    <span className="emoji" aria-hidden>
      {name}
    </span>
  ) : (
    <Circle size={size} aria-hidden />
  );
}
export function Indicator({
  field,
  active,
  onClick,
  language,
  label,
}: {
  field: Field;
  active: boolean;
  onClick: () => void;
  language: Language;
  label?: string;
}) {
  const tint = colors.includes(field.tint || "") ? field.tint : "blue";
  return (
    <button
      type="button"
      className={`indicator ${active ? "active" : ""}`}
      style={{ "--indicator": `var(--${tint})` } as CSSProperties}
      aria-pressed={active}
      aria-label={label || text(field.label, language)}
      title={text(field.label, language)}
      onClick={onClick}
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
      />
    </button>
  );
}
export function BlueMark({ small = false }: { small?: boolean }) {
  return (
    <svg
      className={`blue-mark ${small ? "small" : ""}`}
      viewBox="0 0 84 78"
      fill="none"
      aria-hidden
    >
      <path
        d="M18 52c-6-11-4-27 2-36C29 4 51 3 62 13c9 9 10 29 5 40 10 0 12 7 7 10-4 2-11 0-14-2-9 10-31 10-39 0-4 2-11 4-15 0-3-4 4-9 12-9Z"
        fill="currentColor"
      />
      <path
        d="M28 32v7m23-7v7"
        stroke="white"
        strokeWidth="5"
        strokeLinecap="round"
      />
    </svg>
  );
}
