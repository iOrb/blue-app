export type NoteProposal = { noteID: string; revision: number; title?: string | null; markdown: string };
export type Exchange = { user: string; reply: string; noteProposal?: NoteProposal | null };
const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
const length = (text: string) => [...segmenter.segment(text)].length;
export function validProposal(value: unknown): value is NoteProposal {
  if (!value || typeof value !== "object") return false;
  const p = value as NoteProposal;
  return typeof p.noteID === "string" && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(p.noteID) &&
    Number.isInteger(p.revision) && p.revision >= 0 &&
    (p.title == null || (typeof p.title === "string" && length(p.title) <= 240)) &&
    typeof p.markdown === "string" && length(p.markdown) <= 20000;
}
// Session-only context, including exact unsaved proposals tied to a note revision.
export function validHistory(value: unknown): value is Exchange[] {
  return Array.isArray(value) && value.length <= 4 && value.every((entry) =>
    entry !== null && typeof entry === "object" &&
    typeof entry.user === "string" && length(entry.user) <= 800 &&
    typeof entry.reply === "string" && length(entry.reply) <= 1000 &&
    (entry.noteProposal == null || validProposal(entry.noteProposal)));
}
