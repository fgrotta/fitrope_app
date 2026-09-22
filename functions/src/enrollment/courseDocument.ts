import { CourseTypeValue, tagsMirror, typeTagOf } from "./courseTypes";

/**
 * Costruisce la shape canonica dei corsi V2. I seed usano questa funzione dal
 * codice compilato: id e uid non possono piu divergere dal document id.
 */
export function buildCourseDocument<T extends Record<string, unknown>>(
  input: T & {
    uid: string;
    courseType: CourseTypeValue;
    tag?: string | null;
  }
): T & Record<string, unknown> {
  const tag = input.tag ?? null;
  const typeTag = input.courseType === "personal_trainer"
    ? "Personal Trainer"
    : "Open";
  const result: T & Record<string, unknown> = {
    ...input,
    id: input.uid,
    uid: input.uid,
    tag,
    tags: tagsMirror(typeTag, tag),
    courseModelV2: true,
  };
  // Mantiene il builder agganciato alle regole autoritative, non a una
  // duplicazione fragile nei seed.
  typeTagOf(result);
  return result;
}
