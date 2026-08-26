import {
  canAccessLegacyReadOnlyCourse,
  familyForTypeTag,
  isKnownTypeTag,
  primaryTypeTagForTags,
  typeTagOf,
  TAG_OPEN,
  TAG_HYROX,
  TAG_PERSONAL_TRAINER,
  TAG_HEY_MAMMA,
} from "../enrollment/courseTypes";

describe("course type resolver V1/V2", () => {
  test("famiglie solo Open/PT; Hey Mamma resta storico senza famiglia", () => {
    expect(familyForTypeTag(TAG_OPEN)).toBe("OPEN");
    expect(familyForTypeTag(TAG_PERSONAL_TRAINER)).toBe("PT");
    expect(familyForTypeTag(TAG_HEY_MAMMA)).toBeNull();
    expect(() => familyForTypeTag(TAG_HYROX)).toThrow("type tag sconosciuto");
    expect(isKnownTypeTag(TAG_HYROX)).toBe(false);
  });

  test("V1 deriva il tipo dai tag e tratta Hyrox come Open", () => {
    expect(primaryTypeTagForTags([TAG_HYROX])).toBe(TAG_OPEN);
    expect(typeTagOf({ tags: [TAG_PERSONAL_TRAINER] })).toBe(TAG_PERSONAL_TRAINER);
    expect(typeTagOf({ tags: [TAG_HEY_MAMMA] })).toBe(TAG_HEY_MAMMA);
    expect(typeTagOf({ tags: [] })).toBe(TAG_OPEN);
  });

  test("V2 usa courseType e ignora il tag descrittivo per eligibility", () => {
    expect(typeTagOf({
      courseType: "open",
      tag: "Hyrox",
      courseModelV2: true,
      tags: ["Open", "Hyrox"],
    })).toBe(TAG_OPEN);
  });

  test.each([
    { courseType: "open", tag: "Personal Trainer", tags: ["Open", "Personal Trainer"] },
    { courseType: "personal_trainer", tag: "Yoga", tags: ["Personal Trainer"] },
    { courseType: "open", tag: "Yoga", tags: ["Yoga", "Open"] },
    { courseType: "unknown", tag: null, tags: ["Open"] },
  ])("V2 invalido lancia senza fallback", (data) => {
    expect(() => typeTagOf({ ...data, courseModelV2: true })).toThrow();
  });

  test("accesso legacy speciale solo Hey Mamma", () => {
    expect(canAccessLegacyReadOnlyCourse([TAG_HEY_MAMMA], TAG_HEY_MAMMA)).toBe(true);
    expect(canAccessLegacyReadOnlyCourse([TAG_HYROX], TAG_OPEN)).toBe(false);
  });
});
