// Test delle firestore.rules (categoria D del piano §8) con
// @firebase/rules-unit-testing contro l'emulatore Firestore REALE.
// Girano dentro `npm run test:integration` (emulators:exec). ProjectId
// dedicato (demo-rules-fitrope): i dati delle altre suite non interferiscono
// e le callable (Admin SDK) bypassano comunque le rules.

import { readFileSync } from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";

let env: RulesTestEnvironment;

const ADMIN = "admin-uid";
const TRAINER = "trainer-uid";
const USER = "user-uid";
const OTHER = "other-uid";

/** Doc utente base (campi minimi coerenti con FitropeUser). */
function userDoc(role: string, extra: Record<string, unknown> = {}) {
  return {
    uid: "x",
    email: "x@test.it",
    name: "Nome",
    lastName: "Cognome",
    role,
    courses: [],
    tipologiaCorsoTags: ["Open"],
    ...extra,
  };
}

function courseDoc(extra: Record<string, unknown> = {}) {
  return {
    uid: "c1",
    id: "c1",
    name: "Corso",
    capacity: 10,
    subscribed: 3,
    tags: ["Open"],
    waitlist: [],
    trainerId: TRAINER,
    ...extra,
  };
}

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-rules-fitrope",
    firestore: {
      rules: readFileSync(path.join(__dirname, "../../../firestore.rules"), "utf8"),
    },
  });
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  // Seed con rules disabilitate: attori e documenti bersaglio.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${ADMIN}`).set(userDoc("Admin", { uid: ADMIN }));
    await db.doc(`users/${TRAINER}`).set(userDoc("Trainer", { uid: TRAINER }));
    await db.doc(`users/${USER}`).set(
      userDoc("User", {
        uid: USER,
        tipologiaIscrizione: "PACCHETTO_ENTRATE",
        entrateDisponibili: 5,
        isActive: true,
        enrollmentConsumption: { c9: { kind: "LEGACY_ENTRY" } },
        activeSubscriptions: [],
        cancelledEnrollments: [],
      })
    );
    await db.doc(`users/${OTHER}`).set(userDoc("User", { uid: OTHER }));
    await db.doc("courses/c1").set(courseDoc());
    await db.doc("subscriptions/s1").set({ userId: USER, planKey: "hyrox_10i_3m" });
    await db.doc("subscriptions/s2").set({ userId: OTHER, planKey: "open_2x_1m" });
  });
});

const as = (uid: string) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

describe("rules: users — lettura e registrazione", () => {
  test("lettura: autenticato sì, anonimo no", async () => {
    await assertSucceeds(as(USER).doc(`users/${OTHER}`).get());
    await assertFails(anon().doc(`users/${USER}`).get());
  });

  // Shape canonica scritta da lib/authentication/registration.dart (mirror).
  function registrationDoc(uid: string, over: Record<string, unknown> = {}) {
    return {
      uid,
      email: `${uid}@test.it`,
      createdAt: new Date(),
      name: "N",
      lastName: "C",
      courses: [],
      tipologiaIscrizione: "ABBONAMENTO_PROVA",
      entrateDisponibili: 1,
      entrateSettimanali: 0,
      fineIscrizione: new Date(Date.now() + 30 * 86400 * 1000),
      role: "User",
      numeroTelefono: null,
      isActive: true,
      isAnonymous: false,
      tipologiaCorsoTags: ["Open"],
      emailNotificationsEnabled: true,
      pushNotificationsEnabled: true,
      ...over,
    };
  }

  test("registrazione self con la shape canonica reale → OK", async () => {
    await assertSucceeds(as("new-uid").doc("users/new-uid").set(registrationDoc("new-uid")));
  });

  test("auto-registrazione con privilegi/crediti/tag-premium/trial-esteso → NEGATA", async () => {
    await assertFails(as("evil").doc("users/evil").set(registrationDoc("evil", { role: "Admin" })));
    await assertFails(
      as("evil").doc("users/evil").set(registrationDoc("evil", { entrateDisponibili: 100 }))
    );
    await assertFails(
      as("evil").doc("users/evil").set(registrationDoc("evil", { entrateSettimanali: 999 }))
    );
    // Tag premium auto-grantati: bypasserebbero il gate accesso server-side.
    await assertFails(
      as("evil").doc("users/evil").set(registrationDoc("evil", { tipologiaCorsoTags: ["Tutti i corsi"] }))
    );
    await assertFails(
      as("evil").doc("users/evil").set(registrationDoc("evil", { tipologiaCorsoTags: ["Personal Trainer", "Hyrox"] }))
    );
    // Trial esteso (estende la finestra di scadenza usata da eligibility).
    await assertFails(
      as("evil").doc("users/evil").set(registrationDoc("evil", { fineIscrizione: new Date(2099, 0, 1) }))
    );
    // Campo server-owned aggiunto: hasOnly lo esclude per costruzione.
    await assertFails(
      as("evil").doc("users/evil").set(registrationDoc("evil", { activeSubscriptions: [{ planKey: "hyrox_10i_3m" }] }))
    );
    await assertFails(
      as("evil").doc("users/evil").set(registrationDoc("evil", { enrollmentConsumption: {} }))
    );
    // Doc di un ALTRO uid da utente normale.
    await assertFails(as(USER).doc("users/qualcun-altro").set(registrationDoc("qualcun-altro")));
  });

  test("creazione manuale Admin/Trainer: ok senza campi server-owned; Trainer crea solo User", async () => {
    const manual = {
      uid: "manuale",
      email: "-",
      name: "M",
      lastName: "M",
      role: "User",
      courses: [],
      tipologiaIscrizione: "ABBONAMENTO_PROVA",
      entrateDisponibili: 3,
      cancelledEnrollments: [],
    };
    await assertSucceeds(as(ADMIN).doc("users/manuale").set(manual));
    await assertSucceeds(as(TRAINER).doc("users/manuale2").set({ ...manual, uid: "manuale2" }));
    // Admin può creare Trainer; il Trainer NO (mirror UI: selettore ruolo solo Admin).
    await assertSucceeds(
      as(ADMIN).doc("users/manualeT").set({ ...manual, uid: "manualeT", role: "Trainer" })
    );
    await assertFails(
      as(TRAINER).doc("users/manuale3").set({ ...manual, uid: "manuale3", role: "Trainer" })
    );
    await assertFails(
      as(TRAINER).doc("users/manuale3b").set({ ...manual, uid: "manuale3b", role: "Admin" })
    );
    await assertFails(
      as(ADMIN)
        .doc("users/manuale4")
        .set({ ...manual, uid: "manuale4", enrollmentConsumption: { c1: { kind: "NONE" } } })
    );
    // courses deve nascere vuoto (le iscrizioni passano dal server).
    await assertFails(
      as(ADMIN).doc("users/manuale5").set({ ...manual, uid: "manuale5", courses: ["c1"] })
    );
  });

  // DECISIONE deliberata (vedi commento nelle rules + AVANZAMENTO): un Trainer
  // può creare un cliente manuale con la sua tipologia/tag/entrate. Non è un
  // buco: i doc manuali hanno id casuale ≠ auth-uid → non loggabili.
  test("Trainer crea cliente manuale con tag/entrate specifici → OK (flusso gestionale)", async () => {
    await assertSucceeds(
      as(TRAINER).doc("users/cliente-hyrox").set({
        uid: "cliente-hyrox",
        email: "-",
        name: "Cli",
        lastName: "Ente",
        role: "User",
        courses: [],
        tipologiaIscrizione: "PACCHETTO_ENTRATE",
        entrateDisponibili: 10,
        tipologiaCorsoTags: ["Hyrox"],
        cancelledEnrollments: [],
      })
    );
  });

  test("Trainer NON può grant il tag jolly 'Tutti i corsi' (accesso totale) → NEGATA; Admin sì", async () => {
    const base = {
      email: "-",
      name: "X",
      lastName: "Y",
      role: "User",
      courses: [],
      tipologiaIscrizione: "PACCHETTO_ENTRATE",
      entrateDisponibili: 1,
      tipologiaCorsoTags: ["Tutti i corsi"],
      cancelledEnrollments: [],
    };
    await assertFails(as(TRAINER).doc("users/jolly").set({ ...base, uid: "jolly" }));
    await assertSucceeds(as(ADMIN).doc("users/jollyA").set({ ...base, uid: "jollyA" }));
  });
});

describe("rules: regolamentoAccettatoIl è self-only (acceptRegolamento)", () => {
  test("self scrive la propria accettazione → OK", async () => {
    await assertSucceeds(
      as(USER).doc(`users/${USER}`).update({ regolamentoAccettatoIl: new Date() })
    );
  });

  test("Admin/Trainer per conto di un ALTRO utente → NEGATO (by design, vedi acceptRegolamento.dart)", async () => {
    await assertFails(
      as(ADMIN).doc(`users/${USER}`).update({ regolamentoAccettatoIl: new Date() })
    );
    await assertFails(
      as(TRAINER).doc(`users/${USER}`).update({ regolamentoAccettatoIl: new Date() })
    );
  });
});

describe("rules: users — compatibilità payload REALE della UI (diff-based)", () => {
  // Doc come lo scriveva registration.dart PRIMA del fix shape (chiavi assenti,
  // fineIscrizione con orario arbitrario): è ciò che hanno gli utenti già in
  // produzione. updateUser DEVE poterli salvare.
  const LEGACY = "legacy-uid";
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`users/${LEGACY}`).set({
        uid: LEGACY,
        email: "legacy@test.it",
        name: "Leg",
        lastName: "Acy",
        courses: [],
        tipologiaIscrizione: "ABBONAMENTO_PROVA",
        entrateDisponibili: 1,
        entrateSettimanali: 0,
        fineIscrizione: new Date(Date.now() + 12 * 3600 * 1000 + 30 * 86400 * 1000), // orario non-23:59
        role: "User",
        numeroTelefono: null,
        // NB: niente isActive/isAnonymous/tipologiaCorsoTags/prefs (doc legacy)
      });
    });
  });

  test("self toglie le preferenze: updateUser invia SOLO {emailNotificationsEnabled} → OK", async () => {
    // Payload diff-based reale (lib/api/authentication/updateUser.dart): il
    // self cambia solo le prefs → solo quella chiave, anche se assente nel doc.
    await assertSucceeds(
      env.authenticatedContext(LEGACY).firestore().doc(`users/${LEGACY}`).update({
        emailNotificationsEnabled: false,
      })
    );
  });

  test("self cambia solo il nome → OK (niente fineIscrizione/isActive/tags spuri)", async () => {
    await assertSucceeds(
      env.authenticatedContext(LEGACY).firestore().doc(`users/${LEGACY}`).update({ name: "Nuovo" })
    );
  });

  test("payload VECCHIO-STILE (completo, chiavi aggiunte + fineIscrizione rinormalizzata) → NEGATO (il client non lo produce più)", async () => {
    // Esattamente ciò che faceva la UI prima del fix diff-based: regressione da
    // bloccare se qualcuno reintroduce l'invio del payload completo.
    await assertFails(
      env.authenticatedContext(LEGACY).firestore().doc(`users/${LEGACY}`).update({
        name: "X",
        isActive: true, // chiave aggiunta, valore true → viola whitelist self
        tipologiaCorsoTags: ["Open"], // chiave aggiunta, fuori whitelist
        fineIscrizione: new Date(Date.now() + 30 * 86400 * 1000), // rinormalizzata
      })
    );
  });

  test("Trainer edita un User legacy: updateUser invia SOLO {name} → OK", async () => {
    await assertSucceeds(
      env.authenticatedContext(TRAINER).firestore().doc(`users/${LEGACY}`).update({ name: "Dal trainer" })
    );
  });
});

describe("rules: users — update self (whitelist profilo)", () => {
  test("profilo e preferenze → OK (anche col payload completo invariato)", async () => {
    await assertSucceeds(
      as(USER).doc(`users/${USER}`).update({
        name: "Nuovo",
        numeroTelefono: "1234567890",
        emailNotificationsEnabled: false,
        pushNotificationsEnabled: false,
      })
    );
    await assertSucceeds(
      as(USER).doc(`users/${USER}`).update({ regolamentoAccettatoIl: new Date() })
    );
    // Campi gestionali inclusi ma INVARIATI: diff vuota su di essi → passa.
    await assertSucceeds(
      as(USER).doc(`users/${USER}`).update({
        name: "Ancora",
        role: "User",
        entrateDisponibili: 5,
      })
    );
  });

  test("auto-disattivazione OK, auto-riattivazione NEGATA", async () => {
    await assertSucceeds(as(USER).doc(`users/${USER}`).update({ isActive: false }));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`users/${USER}`).update({ isActive: false });
    });
    await assertFails(as(USER).doc(`users/${USER}`).update({ isActive: true }));
  });

  test("campi critici self → NEGATI (role, crediti, courses, snapshot, registro)", async () => {
    const deny: Record<string, unknown>[] = [
      { role: "Admin" },
      { entrateDisponibili: 99 },
      { entrateSettimanali: 5 },
      { tipologiaIscrizione: "ABBONAMENTO_ANNUALE" },
      { fineIscrizione: new Date(2030, 0, 1) },
      { tipologiaCorsoTags: ["Tutti i corsi"] },
      { courses: ["c1"] },
      { waitlistCourses: ["c1"] },
      { activeSubscriptions: [{ planKey: "hyrox_10i_3m", remainingEntries: 99 }] },
      { enrollmentConsumption: {} },
      { cancelledEnrollments: [{ courseId: "x" }] },
    ];
    for (const update of deny) {
      await assertFails(as(USER).doc(`users/${USER}`).update(update));
    }
  });
});

describe("rules: users — update Admin/Trainer", () => {
  test("Admin: campi gestionali di altri → OK; server-owned → NEGATI", async () => {
    await assertSucceeds(
      as(ADMIN).doc(`users/${USER}`).update({
        role: "Trainer",
        tipologiaIscrizione: "ABBONAMENTO_MENSILE",
        entrateDisponibili: 10,
        entrateSettimanali: 3,
        fineIscrizione: new Date(2026, 11, 31),
        isActive: true,
        tipologiaCorsoTags: ["Open", "Hyrox"],
      })
    );
    for (const update of [
      { courses: ["c1"] },
      { waitlistCourses: ["c1"] },
      { activeSubscriptions: [{ planKey: "x" }] },
      { enrollmentConsumption: {} },
      { cancelledEnrollments: [{ courseId: "x" }] as unknown[] },
      { email: "altro@test.it" },
      { uid: "spoof" },
      { regolamentoAccettatoIl: new Date() }, // marca probatoria self-only
    ]) {
      await assertFails(as(ADMIN).doc(`users/${USER}`).update(update));
    }
  });

  test("Trainer: anagrafica di User → OK; crediti/role o utenti non-User → NEGATI", async () => {
    await assertSucceeds(
      as(TRAINER).doc(`users/${USER}`).update({ name: "T", numeroTelefono: "0000000000" })
    );
    await assertFails(as(TRAINER).doc(`users/${USER}`).update({ entrateDisponibili: 9 }));
    await assertFails(as(TRAINER).doc(`users/${USER}`).update({ role: "Trainer" }));
    await assertFails(as(TRAINER).doc(`users/${ADMIN}`).update({ name: "Hack" }));
  });

  test("delete utente dal client → NEGATA anche per Admin", async () => {
    await assertFails(as(ADMIN).doc(`users/${USER}`).delete());
  });
});

describe("rules: courses", () => {
  test("create Admin/Trainer con contatori azzerati → OK; subscribed>0 / User / id-mismatch / trainerId altrui → NEGATA", async () => {
    await assertSucceeds(as(ADMIN).doc("courses/nuovo").set(courseDoc({ uid: "nuovo", id: "nuovo", subscribed: 0 })));
    // Trainer può creare solo corsi PROPRI (trainerId == proprio uid).
    await assertSucceeds(as(TRAINER).doc("courses/nuovo2").set(courseDoc({ uid: "nuovo2", id: "nuovo2", subscribed: 0, trainerId: TRAINER })));
    await assertFails(as(ADMIN).doc("courses/gonfio").set(courseDoc({ uid: "gonfio", id: "gonfio", subscribed: 5 })));
    await assertFails(as(ADMIN).doc("courses/wl").set(courseDoc({ uid: "wl", id: "wl", subscribed: 0, waitlist: ["u"] })));
    await assertFails(as(USER).doc("courses/abusivo").set(courseDoc({ uid: "abusivo", id: "abusivo", subscribed: 0 })));
    // id non coerente col documentId.
    await assertFails(as(ADMIN).doc("courses/mism").set(courseDoc({ uid: "mism", id: "altro", subscribed: 0 })));
    // Trainer che crea un corso intestato a un ALTRO trainer.
    await assertFails(as(TRAINER).doc("courses/altrui").set(courseDoc({ uid: "altrui", id: "altrui", subscribed: 0, trainerId: "altro-trainer" })));
  });

  test("update: Admin ok; Trainer solo sui propri e senza riassegnare; subscribed/waitlist intoccabili", async () => {
    await assertSucceeds(as(ADMIN).doc("courses/c1").update({ name: "Rinominato", capacity: 12 }));
    await assertSucceeds(as(ADMIN).doc("courses/c1").update({ trainerId: "altro-trainer" })); // Admin può riassegnare
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("courses/c1").set(courseDoc()); // ripristina trainerId == TRAINER
    });
    await assertSucceeds(as(TRAINER).doc("courses/c1").update({ name: "Dal trainer" })); // trainerId == TRAINER
    await assertFails(as(TRAINER).doc("courses/c1").update({ trainerId: "altro-trainer" })); // riassegnazione vietata
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("courses/c2").set(courseDoc({ uid: "c2", id: "c2", trainerId: "altro-trainer" }));
    });
    await assertFails(as(TRAINER).doc("courses/c2").update({ name: "Non mio" }));
    await assertFails(as(ADMIN).doc("courses/c1").update({ subscribed: 99 }));
    await assertFails(as(ADMIN).doc("courses/c1").update({ waitlist: ["u"] }));
    await assertFails(as(USER).doc("courses/c1").update({ name: "Abuso" }));
  });

  test("delete corso dal client → NEGATA anche per Admin (passa dalla callable)", async () => {
    await assertFails(as(ADMIN).doc("courses/c1").delete());
  });
});

describe("rules: subscriptions", () => {
  test("read: solo i propri documenti", async () => {
    await assertSucceeds(as(USER).doc("subscriptions/s1").get());
    await assertFails(as(USER).doc("subscriptions/s2").get());
    await assertFails(anon().doc("subscriptions/s1").get());
  });

  test("write dal client → NEGATA per chiunque (anche Admin)", async () => {
    await assertFails(
      as(USER).doc("subscriptions/s1").update({ remainingEntries: 999 })
    );
    await assertFails(
      as(ADMIN).doc("subscriptions/nuova").set({ userId: USER, planKey: "hyrox_10i_3m" })
    );
    await assertFails(as(ADMIN).doc("subscriptions/s1").delete());
  });
});
