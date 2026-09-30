import { Timestamp } from "firebase-admin/firestore";
import {
  AttendanceInput,
  decideAttendance,
  setAttendanceHandler,
  SELF_WINDOW_BEFORE_MS,
  SELF_WINDOW_AFTER_MS,
  STAFF_WINDOW_BEFORE_MS,
} from "../enrollment/attendance";
import { makeDb, FakeStore, Data } from "./helpers/fakeDb";

const MIN = 60 * 1000;
// Mar 9 giu 2026, 18:00 UTC: inizio del corso di riferimento.
const START = Date.UTC(2026, 5, 9, 18);

function input(over: Partial<AttendanceInput> = {}): AttendanceInput {
  return {
    actorUid: "u1",
    actorRole: "User",
    targetUid: "u1",
    requestedPresent: true,
    courseTrainerId: "t1",
    courseStartMillis: START,
    nowMillis: START,
    targetEnrolled: true,
    existing: null,
    ...over,
  };
}

const staff = (over: Partial<AttendanceInput> = {}) =>
  input({ actorUid: "t1", actorRole: "Trainer", ...over });

describe("decideAttendance — costanti", () => {
  test("finestre: self [-15', +30'], staff da -30'", () => {
    expect(SELF_WINDOW_BEFORE_MS).toBe(15 * MIN);
    expect(SELF_WINDOW_AFTER_MS).toBe(30 * MIN);
    expect(STAFF_WINDOW_BEFORE_MS).toBe(30 * MIN);
  });
});

describe("decideAttendance — ruoli", () => {
  test("Admin e Trainer non possono marcare se stessi", () => {
    for (const role of ["Admin", "Trainer"]) {
      const d = decideAttendance(input({ actorUid: "s", targetUid: "s", actorRole: role }));
      expect(d).toMatchObject({ allowed: false, reason: "ATTENDANCE_STAFF_CANNOT_SELF_MARK" });
    }
  });

  test("un socio non può marcare un altro socio", () => {
    const d = decideAttendance(input({ targetUid: "u2" }));
    expect(d).toMatchObject({ allowed: false, reason: "ATTENDANCE_NOT_STAFF" });
  });

  test("ruolo sconosciuto (null) su altro utente → NOT_STAFF", () => {
    const d = decideAttendance(input({ actorRole: null, targetUid: "u2" }));
    expect(d).toMatchObject({ allowed: false, reason: "ATTENDANCE_NOT_STAFF" });
  });

  test("Trainer su corso di un altro trainer → NOT_COURSE_TRAINER", () => {
    const d = decideAttendance(staff({ targetUid: "u1", courseTrainerId: "t2" }));
    expect(d).toMatchObject({ allowed: false, reason: "ATTENDANCE_NOT_COURSE_TRAINER" });
  });

  test("Trainer titolare o corso senza trainer → ammesso", () => {
    for (const trainerId of ["t1", null, ""]) {
      const d = decideAttendance(staff({ courseTrainerId: trainerId }));
      expect(d).toMatchObject({ allowed: true, source: "trainer" });
    }
  });

  test("Admin su corso di qualunque trainer → ammesso con source admin", () => {
    const d = decideAttendance(staff({ actorUid: "a1", actorRole: "Admin", courseTrainerId: "t2" }));
    expect(d).toMatchObject({ allowed: true, source: "admin" });
  });

  test("self → source self", () => {
    expect(decideAttendance(input())).toMatchObject({ allowed: true, source: "self" });
  });
});

describe("decideAttendance — precondizioni", () => {
  test("il socio non può dichiararsi assente", () => {
    const d = decideAttendance(input({ requestedPresent: false }));
    expect(d).toMatchObject({ allowed: false, reason: "ATTENDANCE_SELF_CANNOT_MARK_ABSENT" });
  });

  test("target non iscritto → NOT_ENROLLED, anche per lo staff", () => {
    expect(decideAttendance(input({ targetEnrolled: false }))).toMatchObject({
      allowed: false,
      reason: "ATTENDANCE_NOT_ENROLLED",
    });
    expect(decideAttendance(staff({ targetEnrolled: false }))).toMatchObject({
      allowed: false,
      reason: "ATTENDANCE_NOT_ENROLLED",
    });
  });
});

describe("decideAttendance — finestre (bordi inclusivi)", () => {
  test.each([
    [-15 * MIN - 1, "ATTENDANCE_WINDOW_NOT_OPEN"],
    [-15 * MIN, null],
    [0, null],
    [30 * MIN, null],
    [30 * MIN + 1, "ATTENDANCE_WINDOW_CLOSED"],
  ])("self a %d ms dall'inizio → %s", (offset, reason) => {
    const d = decideAttendance(input({ nowMillis: START + offset }));
    if (reason === null) expect(d.allowed).toBe(true);
    else expect(d).toMatchObject({ allowed: false, reason });
  });

  test.each([
    [-30 * MIN - 1, "ATTENDANCE_WINDOW_NOT_OPEN"],
    [-30 * MIN, null],
    [3 * 24 * 60 * MIN, null],
  ])("staff a %d ms dall'inizio → %s", (offset, reason) => {
    const d = decideAttendance(staff({ nowMillis: START + offset }));
    if (reason === null) expect(d.allowed).toBe(true);
    else expect(d).toMatchObject({ allowed: false, reason });
  });
});

describe("decideAttendance — record esistente", () => {
  test("self con record dello staff (presente o assente) → ALREADY_RECORDED_BY_STAFF", () => {
    for (const present of [true, false]) {
      for (const source of ["trainer", "admin"] as const) {
        const d = decideAttendance(input({ existing: { present, source } }));
        expect(d).toMatchObject({
          allowed: false,
          reason: "ATTENDANCE_ALREADY_RECORDED_BY_STAFF",
        });
      }
    }
  });

  test("self già presente → noop idempotente", () => {
    const d = decideAttendance(input({ existing: { present: true, source: "self" } }));
    expect(d).toMatchObject({ allowed: true, noop: true, presentDelta: 0 });
  });

  test("staff che ripete lo stesso stato con la stessa fonte → noop", () => {
    const d = decideAttendance(staff({ existing: { present: true, source: "trainer" } }));
    expect(d).toMatchObject({ allowed: true, noop: true, presentDelta: 0 });
  });

  test.each([
    // [existing, requested, source, delta]
    [null, true, "trainer", 1],
    [null, false, "trainer", 0],
    [{ present: true, source: "self" }, true, "trainer", 0],
    [{ present: true, source: "self" }, false, "trainer", -1],
    [{ present: false, source: "trainer" }, true, "trainer", 1],
    [{ present: true, source: "trainer" }, false, "trainer", -1],
    [{ present: true, source: "trainer" }, true, "admin", 0],
  ] as const)("staff: %j → present=%s (%s) → delta %d", (existing, requested, src, delta) => {
    const actor = src === "admin" ? { actorUid: "a1", actorRole: "Admin" } : {};
    const d = decideAttendance(
      staff({ ...actor, existing: existing ?? null, requestedPresent: requested })
    );
    expect(d).toMatchObject({ allowed: true, noop: false, presentDelta: delta, source: src });
  });

  test("self senza record → delta +1", () => {
    expect(decideAttendance(input())).toMatchObject({ noop: false, presentDelta: 1 });
  });
});

// ----- handler -----

const auth = (uid: string) => ({ auth: { uid } });

function course(over: Data = {}): Data {
  return {
    uid: "c1",
    name: "Corso Open",
    trainerId: "t1",
    startDate: Timestamp.fromMillis(START),
    endDate: Timestamp.fromMillis(START + 60 * MIN),
    tags: ["Open"],
    ...over,
  };
}

function baseStore(over: Partial<FakeStore> = {}): FakeStore {
  return {
    users: {
      u1: { uid: "u1", role: "User", courses: ["c1"] },
      u2: { uid: "u2", role: "User", courses: ["c1"] },
      u3: { uid: "u3", role: "User", courses: [] },
      t1: { uid: "t1", role: "Trainer" },
      t2: { uid: "t2", role: "Trainer" },
      a1: { uid: "a1", role: "Admin" },
    },
    courses: { c1: course() },
    subs: {},
    attendance: {},
    ...over,
  };
}

async function expectRejection(p: Promise<unknown>, code: string, reason?: string) {
  const err = await p.then(
    () => {
      throw new Error("attesa rejection");
    },
    (e) => e
  );
  expect(err).toMatchObject({ code });
  if (reason) expect(err.details).toEqual({ reason });
}

describe("setAttendanceHandler", () => {
  test("self check-in: scrive il doc deterministico e il marcatore sul corso", async () => {
    const store = baseStore();
    const res = await setAttendanceHandler(
      { ...auth("u1"), data: { courseId: "c1", present: true } },
      makeDb(store),
      START - 5 * MIN
    );
    expect(res).toEqual({ ok: true, present: true, source: "self", changed: true, presentCount: 1 });
    const doc = store.attendance!["c1_u1"];
    expect(doc).toMatchObject({
      courseId: "c1",
      userId: "u1",
      courseStartMillis: START,
      present: true,
      source: "self",
      markedBy: "u1",
    });
    expect((doc.markedAt as Timestamp).toMillis()).toBe(START - 5 * MIN);
    expect((doc.updatedAt as Timestamp).toMillis()).toBe(START - 5 * MIN);
    const marker = store.courses.c1.attendance as Data;
    expect(marker.presentCount).toBe(1);
    expect(marker.lastMarkedBy).toBe("u1");
    expect((marker.lastMarkedAt as Timestamp).toMillis()).toBe(START - 5 * MIN);
  });

  test("self doppio tap: changed false e store invariato", async () => {
    const store = baseStore();
    const db = makeDb(store);
    await setAttendanceHandler({ ...auth("u1"), data: { courseId: "c1", present: true } }, db, START);
    const before = JSON.parse(JSON.stringify(store));
    const res = await setAttendanceHandler(
      { ...auth("u1"), data: { courseId: "c1", present: true } },
      db,
      START + MIN
    );
    expect(res).toEqual({ ok: true, present: true, source: "self", changed: false, presentCount: 1 });
    expect(JSON.parse(JSON.stringify(store))).toEqual(before);
  });

  test("il trainer sovrascrive il self: markedAt resta il primo istante", async () => {
    const store = baseStore();
    const db = makeDb(store);
    await setAttendanceHandler({ ...auth("u1"), data: { courseId: "c1", present: true } }, db, START);
    const res = await setAttendanceHandler(
      { ...auth("t1"), data: { courseId: "c1", userId: "u1", present: false } },
      db,
      START + 10 * MIN
    );
    expect(res).toEqual({ ok: true, present: false, source: "trainer", changed: true, presentCount: 0 });
    const doc = store.attendance!["c1_u1"];
    expect(doc).toMatchObject({ present: false, source: "trainer", markedBy: "t1" });
    expect((doc.markedAt as Timestamp).toMillis()).toBe(START);
    expect((doc.updatedAt as Timestamp).toMillis()).toBe(START + 10 * MIN);
    expect((store.courses.c1.attendance as Data).lastMarkedBy).toBe("t1");
  });

  test("dopo il record dello staff il socio riceve details.reason", async () => {
    const store = baseStore();
    const db = makeDb(store);
    await setAttendanceHandler(
      { ...auth("t1"), data: { courseId: "c1", userId: "u1", present: false } },
      db,
      START
    );
    await expectRejection(
      setAttendanceHandler({ ...auth("u1"), data: { courseId: "c1", present: true } }, db, START),
      "failed-precondition",
      "ATTENDANCE_ALREADY_RECORDED_BY_STAFF"
    );
  });

  test("assenza su doc nuovo: record creato, presentCount 0, marcatore presente", async () => {
    const store = baseStore();
    const res = await setAttendanceHandler(
      { ...auth("t1"), data: { courseId: "c1", userId: "u2", present: false } },
      makeDb(store),
      START
    );
    expect(res).toMatchObject({ changed: true, presentCount: 0 });
    expect(store.attendance!["c1_u2"]).toMatchObject({ present: false });
    expect(store.courses.c1.attendance).toMatchObject({ presentCount: 0, lastMarkedBy: "t1" });
  });

  test("presentCount parte dal marcatore esistente ed è clampato a 0", async () => {
    const store = baseStore({
      courses: { c1: course({ attendance: { presentCount: 0, lastMarkedBy: "x" } }) },
      attendance: {
        c1_u1: { courseId: "c1", userId: "u1", present: true, source: "self" },
      },
    });
    const res = await setAttendanceHandler(
      { ...auth("a1"), data: { courseId: "c1", userId: "u1", present: false } },
      makeDb(store),
      START
    );
    expect(res).toMatchObject({ source: "admin", presentCount: 0 });
  });

  test("due soci: presentCount 2", async () => {
    const store = baseStore();
    const db = makeDb(store);
    await setAttendanceHandler({ ...auth("u1"), data: { courseId: "c1", present: true } }, db, START);
    const res = await setAttendanceHandler(
      { ...auth("t1"), data: { courseId: "c1", userId: "u2", present: true } },
      db,
      START
    );
    expect(res).toMatchObject({ presentCount: 2 });
  });

  test("rifiuti con code e details.reason", async () => {
    const db = makeDb(baseStore());
    await expectRejection(
      setAttendanceHandler({ ...auth("u1"), data: { courseId: "c1", userId: "u2", present: true } }, db, START),
      "permission-denied",
      "ATTENDANCE_NOT_STAFF"
    );
    await expectRejection(
      setAttendanceHandler({ ...auth("t2"), data: { courseId: "c1", userId: "u1", present: true } }, db, START),
      "permission-denied",
      "ATTENDANCE_NOT_COURSE_TRAINER"
    );
    await expectRejection(
      setAttendanceHandler({ ...auth("u3"), data: { courseId: "c1", present: true } }, db, START),
      "failed-precondition",
      "ATTENDANCE_NOT_ENROLLED"
    );
    await expectRejection(
      setAttendanceHandler({ ...auth("t1"), data: { courseId: "c1", userId: "ghost", present: true } }, db, START),
      "failed-precondition",
      "ATTENDANCE_NOT_ENROLLED"
    );
    await expectRejection(
      setAttendanceHandler({ ...auth("u1"), data: { courseId: "c1", present: true } }, db, START + 31 * MIN),
      "failed-precondition",
      "ATTENDANCE_WINDOW_CLOSED"
    );
    await expectRejection(
      setAttendanceHandler({ ...auth("u1"), data: { courseId: "c1", present: true } }, db, START - 16 * MIN),
      "failed-precondition",
      "ATTENDANCE_WINDOW_NOT_OPEN"
    );
    await expectRejection(
      setAttendanceHandler({ ...auth("u1"), data: { courseId: "c1", present: false } }, db, START),
      "permission-denied",
      "ATTENDANCE_SELF_CANNOT_MARK_ABSENT"
    );
  });

  test("validazione input", async () => {
    const db = makeDb(baseStore());
    await expectRejection(
      setAttendanceHandler({ auth: null, data: { courseId: "c1", present: true } }, db, START),
      "unauthenticated"
    );
    await expectRejection(
      setAttendanceHandler({ ...auth("u1"), data: { present: true } }, db, START),
      "invalid-argument"
    );
    await expectRejection(
      setAttendanceHandler({ ...auth("u1"), data: { courseId: "c1", present: "si" } }, db, START),
      "invalid-argument"
    );
    await expectRejection(
      setAttendanceHandler({ ...auth("t1"), data: { courseId: "c1", userId: 3, present: true } }, db, START),
      "invalid-argument"
    );
    await expectRejection(
      setAttendanceHandler({ ...auth("u1"), data: { courseId: "zzz", present: true } }, db, START),
      "not-found"
    );
  });
});
