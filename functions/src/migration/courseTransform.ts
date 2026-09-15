import {
  CourseMigrationTarget,
  MigrationDecision,
} from "./types";
import {
  SELECTABLE_TAGS,
  TAG_HEY_MAMMA,
  TAG_OPEN,
  TAG_PERSONAL_TRAINER,
  tagsMirror,
  typeTagForCourseType,
} from "../enrollment/courseTypes";

type Data = Record<string, unknown>;

function sameList(left: unknown, right: string[]): boolean {
  return Array.isArray(left) &&
    left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

export function targetMatchesCourse(
  data: Data,
  target: CourseMigrationTarget
): boolean {
  return data.courseModelV2 === true &&
    data.courseType === target.courseType &&
    data.tag === target.tag &&
    sameList(data.tags, target.tags);
}

function existingV2Target(data: Data): CourseMigrationTarget | null {
  if (data.courseModelV2 !== true) return null;
  try {
    const typeTag = typeTagForCourseType(data.courseType);
    const tag = data.tag;
    if (tag !== null &&
        (typeof tag !== "string" ||
          !SELECTABLE_TAGS.includes(tag as typeof SELECTABLE_TAGS[number]))) {
      return null;
    }
    if (typeTag === TAG_PERSONAL_TRAINER && tag !== TAG_PERSONAL_TRAINER) {
      return null;
    }
    if (typeTag === TAG_OPEN && tag === TAG_PERSONAL_TRAINER) return null;
    const target: CourseMigrationTarget = {
      courseType: data.courseType as CourseMigrationTarget["courseType"],
      tag: tag as string | null,
      courseModelV2: true,
      tags: tagsMirror(typeTag, tag as string | null),
    };
    return targetMatchesCourse(data, target) ? target : null;
  } catch (_) {
    return null;
  }
}

export function transformCourse(
  data: Data
): MigrationDecision<CourseMigrationTarget> {
  if (data.courseModelV2 === true) {
    const target = existingV2Target(data);
    return target === null
      ? {
          conversionStatus: "TARGET_CONFLICT",
          reasonCode: "INVALID_TAG_SHAPE",
          reasonDetail: "documento V2 con shape o mirror non validi",
          target: null,
        }
      : {
          conversionStatus: "ALREADY_APPLIED",
          reasonCode: "ALREADY_APPLIED",
          reasonDetail: "documento corso gia conforme al modello V2",
          target,
        };
  }

  const raw = data.tags;
  if (raw !== undefined &&
      (!Array.isArray(raw) || raw.some((value) => typeof value !== "string"))) {
    return ignored("INVALID_TAG_SHAPE", "tags non e una lista di stringhe");
  }
  const tags = (raw ?? []) as string[];
  if (tags.includes(TAG_HEY_MAMMA)) {
    return ignored("HEY_MAMMA", "corso storico Hey Mamma in sola lettura");
  }

  let target: CourseMigrationTarget;
  if (tags.length === 0 ||
      (tags.length === 1 && tags[0] === TAG_OPEN)) {
    target = {
      courseType: "open",
      tag: null,
      courseModelV2: true,
      tags: [TAG_OPEN],
    };
  } else if (tags.length === 1 && tags[0] === TAG_PERSONAL_TRAINER) {
    target = {
      courseType: "personal_trainer",
      tag: TAG_PERSONAL_TRAINER,
      courseModelV2: true,
      tags: [TAG_PERSONAL_TRAINER],
    };
  } else {
    return ignored(
      "INVALID_TAG_SHAPE",
      `shape legacy non convertibile: ${JSON.stringify(tags)}`
    );
  }

  return {
    conversionStatus: "CONVERTIBLE",
    reasonCode: "OK",
    reasonDetail: "shape legacy riconosciuta esattamente",
    target,
  };
}

function ignored(
  reasonCode: "HEY_MAMMA" | "INVALID_TAG_SHAPE",
  reasonDetail: string
): MigrationDecision<CourseMigrationTarget> {
  return {
    conversionStatus: "IGNORED",
    reasonCode,
    reasonDetail,
    target: null,
  };
}

