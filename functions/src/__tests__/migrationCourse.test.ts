import {
  targetMatchesCourse,
  transformCourse,
} from "../migration/courseTransform";

describe("course migration matrix", () => {
  test.each([
    ["campo assente", {}, "open", null, ["Open"]],
    ["lista vuota", { tags: [] }, "open", null, ["Open"]],
    ["Open", { tags: ["Open"] }, "open", null, ["Open"]],
    [
      "Personal Trainer",
      { tags: ["Personal Trainer"] },
      "personal_trainer",
      "Personal Trainer",
      ["Personal Trainer"],
    ],
  ])("converte %s", (_, source, courseType, tag, tags) => {
    const result = transformCourse(source);
    expect(result.conversionStatus).toBe("CONVERTIBLE");
    expect(result.target).toEqual({
      courseType,
      tag,
      courseModelV2: true,
      tags,
    });
  });

  test.each([
    [["Hey Mamma"], "HEY_MAMMA"],
    [["Open", "Hey Mamma"], "HEY_MAMMA"],
    [["Open", "Personal Trainer"], "INVALID_TAG_SHAPE"],
    [["Yoga"], "INVALID_TAG_SHAPE"],
  ])("ignora %j con %s", (tags, reason) => {
    const result = transformCourse({ tags });
    expect(result.conversionStatus).toBe("IGNORED");
    expect(result.reasonCode).toBe(reason);
    expect(result.target).toBeNull();
  });

  test("un V2 esatto e ALREADY_APPLIED", () => {
    const data = {
      courseType: "open",
      tag: "Yoga",
      courseModelV2: true,
      tags: ["Open", "Yoga"],
    };
    const result = transformCourse(data);
    expect(result.conversionStatus).toBe("ALREADY_APPLIED");
    expect(targetMatchesCourse(data, result.target!)).toBe(true);
  });

  test.each([
    { courseType: "open", tag: "Personal Trainer", tags: ["Open", "Personal Trainer"] },
    { courseType: "personal_trainer", tag: "Yoga", tags: ["Personal Trainer"] },
    { courseType: "open", tag: "Yoga", tags: ["Yoga", "Open"] },
    { courseType: "open", tag: "Yoga", tags: ["Open", "Yoga", "Tabata"] },
  ])("un V2 incoerente e TARGET_CONFLICT", (shape) => {
    const result = transformCourse({ ...shape, courseModelV2: true });
    expect(result.conversionStatus).toBe("TARGET_CONFLICT");
  });
});

