// Resolver centralizzato del modello corso, mirror di lib/types/course.dart.
// `courseType` e autoritativo solo sui documenti marcati courseModelV2=true;
// i documenti V1 continuano a essere risolti dai tag durante il rollout.

import { SubscriptionFamily } from "./plansCatalog";

export const TAG_OPEN = "Open";
export const TAG_PERSONAL_TRAINER = "Personal Trainer";
export const TAG_HYROX = "Hyrox";
export const TAG_HEY_MAMMA = "Hey Mamma";

export const SELECTABLE_TAGS = [
  TAG_PERSONAL_TRAINER,
  TAG_HYROX,
  "Yoga",
  "Pilates",
  "Calisthenics",
  "Posturale",
  "Tabata",
  "Fitrope",
] as const;

export const ALL_TAGS = [...SELECTABLE_TAGS];

export type CourseTypeValue = "open" | "personal_trainer";
export type CourseDocument = Record<string, unknown>;

const FAMILY_BY_TYPE_TAG: Record<string, SubscriptionFamily | null> = {
  [TAG_OPEN]: "OPEN",
  [TAG_PERSONAL_TRAINER]: "PT",
  // Storico V1 in sola lettura: conserva l'assenza di limiti finche l'admin
  // non bonifica i documenti Hey Mamma esclusi dal backfill.
  [TAG_HEY_MAMMA]: null,
};

export function isKnownTypeTag(tag: string): boolean {
  return Object.prototype.hasOwnProperty.call(FAMILY_BY_TYPE_TAG, tag);
}

export function familyForTypeTag(tag: string): SubscriptionFamily | null {
  if (!isKnownTypeTag(tag)) {
    throw new Error(`type tag sconosciuto: ${tag}`);
  }
  return FAMILY_BY_TYPE_TAG[tag];
}

export function typeTagForCourseType(value: unknown): string {
  if (value === "open") return TAG_OPEN;
  if (value === "personal_trainer") return TAG_PERSONAL_TRAINER;
  throw new Error(`courseType sconosciuto: ${String(value)}`);
}

/**
 * Resolver storico. Hyrox e ora un tag descrittivo di Open; Hey Mamma resta
 * riconoscibile solo per conservare il comportamento dei documenti esclusi.
 */
export function primaryTypeTagForTags(tags: string[]): string {
  if (tags.includes(TAG_HEY_MAMMA)) return TAG_HEY_MAMMA;
  if (tags.includes(TAG_PERSONAL_TRAINER) && !tags.includes(TAG_OPEN)) {
    return TAG_PERSONAL_TRAINER;
  }
  return TAG_OPEN;
}

export function legacyTagsOf(course: CourseDocument): string[] {
  const raw = course.tags;
  if (raw === undefined) return [];
  if (!Array.isArray(raw) || raw.some((value) => typeof value !== "string")) {
    throw new Error("tags deve essere una lista di stringhe");
  }
  return raw as string[];
}

export function tagsMirror(typeTag: string, tag: string | null): string[] {
  return tag === null || tag === typeTag ? [typeTag] : [typeTag, tag];
}

/** Tipo effettivo usato da eligibility, waitlist, refund e conteggi. */
export function typeTagOf(course: CourseDocument): string {
  if (course.courseModelV2 !== true) {
    return primaryTypeTagForTags(legacyTagsOf(course));
  }

  const typeTag = typeTagForCourseType(course.courseType);
  const tag = course.tag;
  if (tag !== null &&
      (typeof tag !== "string" || !SELECTABLE_TAGS.includes(tag as typeof SELECTABLE_TAGS[number]))) {
    throw new Error(`tag corso V2 sconosciuto: ${String(tag)}`);
  }
  if (typeTag === TAG_PERSONAL_TRAINER && tag !== TAG_PERSONAL_TRAINER) {
    throw new Error("shape V2 PT senza tag Personal Trainer");
  }
  if (typeTag === TAG_OPEN && tag === TAG_PERSONAL_TRAINER) {
    throw new Error("shape V2 Open con tag Personal Trainer");
  }

  const actual = legacyTagsOf(course);
  const expected = tagsMirror(typeTag, tag as string | null);
  if (actual.length !== expected.length || actual.some((v, i) => v !== expected[i])) {
    throw new Error(`mirror tags V2 invalido: ${JSON.stringify(actual)}`);
  }
  return typeTag;
}

/** Compatibilita limitata ai corsi storici Hey Mamma. */
export function canAccessLegacyReadOnlyCourse(
  userTags: string[],
  courseTypeTag: string
): boolean {
  return courseTypeTag === TAG_HEY_MAMMA &&
    (userTags.includes(TAG_HEY_MAMMA) || userTags.includes("Tutti i corsi"));
}
