// Mirror server-side del registry tipologie/tag Dart
// (lib/utils/course_types.dart + lib/utils/course_tags.dart).
// Le chiavi/tag DEVONO restare identiche tra client e server.

import { SubscriptionFamily } from "./plansCatalog";

export const TAG_OPEN = "Open";
export const TAG_PERSONAL_TRAINER = "Personal Trainer";
export const TAG_HYROX = "Hyrox";
export const TAG_HEY_MAMMA = "Hey Mamma";

/** Tutti i tag/tipologie noti. */
export const ALL_TAGS = [
  TAG_PERSONAL_TRAINER,
  TAG_OPEN,
  TAG_HYROX,
  TAG_HEY_MAMMA,
];

/**
 * Famiglia di abbonamento che "consuma" una tipologia di corso (null = nessun
 * abbonamento dedicato, es. Hey Mamma). Mirror di `CourseTypes.*.family`.
 */
const FAMILY_BY_TAG: Record<string, SubscriptionFamily | null> = {
  [TAG_OPEN]: "OPEN",
  [TAG_PERSONAL_TRAINER]: "PT",
  [TAG_HYROX]: "HYROX",
  [TAG_HEY_MAMMA]: null,
};

/** True se [tag] è una tipologia di corso registrata. */
export function isKnownTypeTag(tag: string): boolean {
  return Object.prototype.hasOwnProperty.call(FAMILY_BY_TAG, tag);
}

/** Famiglia che sblocca/consuma la tipologia [tag], o null. */
export function familyForTypeTag(tag: string): SubscriptionFamily | null {
  return FAMILY_BY_TAG[tag] ?? null;
}

/**
 * Tipologia "primaria" di un corso: primo tag riconosciuto, altrimenti `Open`.
 * Determina in modo DETERMINISTICO quale famiglia consuma il corso (mirror di
 * `_coursePrimaryTypeTag` in getCourseState.dart: primaryForTags() ?? OPEN).
 */
export function primaryTypeTagForTags(tags: string[]): string {
  for (const tag of tags) {
    if (isKnownTypeTag(tag)) return tag;
  }
  return TAG_OPEN;
}

/**
 * Mirror di `CourseTags.canUserAccessCourse` (lib/utils/course_tags.dart):
 * accesso al corso basato sui tag legacy dell'utente.
 */
export function canUserAccessCourse(
  userTags: string[],
  courseTags: string[]
): boolean {
  if (userTags.includes("Tutti i corsi")) return true;

  const userEmpty = userTags.length === 0;
  const courseEmpty = courseTags.length === 0;

  if (
    (userEmpty && courseEmpty) ||
    (userEmpty && courseTags.includes(TAG_OPEN)) ||
    (userTags.includes(TAG_OPEN) && courseEmpty)
  ) {
    return true;
  }

  return userTags.some((t) => courseTags.includes(t));
}
