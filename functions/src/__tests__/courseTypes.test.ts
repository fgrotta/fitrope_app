import {
  canUserAccessCourse,
  familyForTypeTag,
  isKnownTypeTag,
  primaryTypeTagForTags,
  TAG_OPEN,
  TAG_HYROX,
  TAG_PERSONAL_TRAINER,
  TAG_HEY_MAMMA,
} from "../enrollment/courseTypes";

describe("courseTypes registry", () => {
  test("famiglia per tipologia (1:1) e Hey Mamma senza famiglia", () => {
    expect(familyForTypeTag(TAG_OPEN)).toBe("OPEN");
    expect(familyForTypeTag(TAG_HYROX)).toBe("HYROX");
    expect(familyForTypeTag(TAG_PERSONAL_TRAINER)).toBe("PT");
    expect(familyForTypeTag(TAG_HEY_MAMMA)).toBeNull();
    expect(familyForTypeTag("Sconosciuto")).toBeNull();
  });

  test("isKnownTypeTag", () => {
    expect(isKnownTypeTag(TAG_OPEN)).toBe(true);
    expect(isKnownTypeTag(TAG_HEY_MAMMA)).toBe(true);
    expect(isKnownTypeTag("Boh")).toBe(false);
  });

  test("primaryTypeTagForTags: primo tag noto, fallback Open", () => {
    expect(primaryTypeTagForTags([TAG_HYROX, TAG_OPEN])).toBe(TAG_HYROX);
    expect(primaryTypeTagForTags(["Sconosciuto", TAG_PERSONAL_TRAINER])).toBe(
      TAG_PERSONAL_TRAINER
    );
    expect(primaryTypeTagForTags([])).toBe(TAG_OPEN);
    expect(primaryTypeTagForTags(["Sconosciuto"])).toBe(TAG_OPEN);
  });
});

describe("canUserAccessCourse (mirror Dart)", () => {
  test("'Tutti i corsi' sblocca qualsiasi corso", () => {
    expect(canUserAccessCourse(["Tutti i corsi"], [TAG_HYROX])).toBe(true);
  });

  test("utente vuoto + corso vuoto/Open", () => {
    expect(canUserAccessCourse([], [])).toBe(true);
    expect(canUserAccessCourse([], [TAG_OPEN])).toBe(true);
    expect(canUserAccessCourse([TAG_OPEN], [])).toBe(true);
  });

  test("almeno un tag in comune", () => {
    expect(canUserAccessCourse([TAG_OPEN, TAG_HYROX], [TAG_HYROX])).toBe(true);
    expect(canUserAccessCourse([TAG_OPEN], [TAG_HYROX])).toBe(false);
  });

  test("utente vuoto ma corso con tag != Open → no accesso", () => {
    expect(canUserAccessCourse([], [TAG_HYROX])).toBe(false);
  });
});
