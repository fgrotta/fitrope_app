/* eslint-disable no-console */
// Seed sintetico per la Firebase Emulator Suite (vedi docs/AMBIENTI_DI_TEST.md).
//
// Uso:   cd functions && npm run build && npm run seed:emulator
// (gli emulatori devono essere già avviati: `firebase emulators:start`)
//
// Crea utenti Auth+Firestore (password unica: test1234), corsi della settimana
// PROSSIMA e un abbonamento nuovo-modello con snapshot. Catalogo piani e shape
// dei documenti vengono dal codice COMPILATO (functions/lib): il seed non
// DIVERGE mai dalla logica reale.
//
// SICUREZZA: gli host degli emulatori vengono impostati qui sotto in modo
// INCONDIZIONATO, prima di inizializzare l'Admin SDK → è strutturalmente
// impossibile colpire produzione (un eventuale valore pre-esistente
// nell'ambiente viene sovrascritto; per host non standard modificare qui).

process.env.FIRESTORE_EMULATOR_HOST = "localhost:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "localhost:9099";

const admin = require("firebase-admin");
const { Timestamp } = require("firebase-admin/firestore");
const { planByKey } = require("../lib/enrollment/plansCatalog");
const {
  buildSubscriptionFromPlan,
  recordToDoc,
  recordToSnapshotEntry,
} = require("../lib/enrollment/subscription");

admin.initializeApp({ projectId: "fit-rope-app-1f575" });
const db = admin.firestore();

const PASSWORD = "test1234";

/**
 * Giorno della settimana PROSSIMA alle [hour] locali (corsi sempre nel futuro):
 * dayOffset 0 = lunedì, 1 = martedì, … 5 = sabato.
 */
function nextWeekDayAt(hour, dayOffset = 0) {
  const now = new Date();
  const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  monday.setDate(monday.getDate() + ((8 - monday.getDay()) % 7 || 7));
  monday.setDate(monday.getDate() + dayOffset);
  monday.setHours(hour, 0, 0, 0);
  return monday;
}

function baseUser(uid, email, name, lastName, role, extra = {}) {
  return {
    uid,
    email,
    name,
    lastName,
    role,
    courses: [],
    tipologiaIscrizione: null,
    entrateDisponibili: null,
    entrateSettimanali: null,
    fineIscrizione: null,
    isActive: true,
    isAnonymous: false,
    createdAt: Timestamp.now(),
    certificatoScadenza: Timestamp.fromDate(
      new Date(Date.now() + 180 * 86400000)
    ),
    numeroTelefono: null,
    tipologiaCorsoTags: ["Open"],
    cancelledEnrollments: [],
    regolamentoAccettatoIl: Timestamp.now(),
    waitlistCourses: [],
    emailNotificationsEnabled: true,
    pushNotificationsEnabled: true,
    activeSubscriptions: [],
    ...extra,
  };
}

function course(uid, name, tags, start, capacity, subscribed, extra = {}) {
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  return {
    id: uid,
    uid,
    name,
    startDate: Timestamp.fromDate(start),
    endDate: Timestamp.fromDate(end),
    capacity,
    subscribed,
    trainerId: "trainer-test",
    tags,
    waitlist: [],
    reminderEnabled: true,
    waitlistEnabled: true,
    sala: tags.includes("Hyrox") ? "Sala 2" : "Sala 1",
    ...extra,
  };
}

async function createAuthUser(uid, email, displayName) {
  try {
    await admin.auth().createUser({
      uid,
      email,
      password: PASSWORD,
      displayName,
      emailVerified: true,
    });
  } catch (e) {
    if (e.code === "auth/uid-already-exists") {
      console.log(`  (auth ${uid} già presente, skip)`);
      return;
    }
    throw e;
  }
}

async function main() {
  console.log("Seed emulatore — utenti (password: %s)", PASSWORD);

  const users = [
    {
      uid: "admin-test",
      email: "admin@test.it",
      doc: baseUser("admin-test", "admin@test.it", "Anna", "Admin", "Admin", {
        tipologiaCorsoTags: ["Tutti i corsi"],
      }),
    },
    {
      uid: "trainer-test",
      email: "trainer@test.it",
      doc: baseUser("trainer-test", "trainer@test.it", "Teo", "Trainer", "Trainer"),
    },
    {
      // Legacy a ingressi: 5 entrate residue.
      uid: "pacchetto-test",
      email: "pacchetto@test.it",
      doc: baseUser("pacchetto-test", "pacchetto@test.it", "Paola", "Pacchetto", "User", {
        tipologiaIscrizione: "PACCHETTO_ENTRATE",
        entrateDisponibili: 5,
      }),
    },
    {
      // Legacy temporale: 2 ingressi/settimana, scade tra 60 giorni.
      uid: "mensile-test",
      email: "mensile@test.it",
      doc: baseUser("mensile-test", "mensile@test.it", "Mario", "Mensile", "User", {
        tipologiaIscrizione: "ABBONAMENTO_MENSILE",
        entrateSettimanali: 2,
        fineIscrizione: Timestamp.fromDate(new Date(Date.now() + 60 * 86400000)),
      }),
    },
    {
      // Utente in prova: 1 entrata (per il flusso promemoria prova).
      uid: "prova-test",
      email: "prova@test.it",
      doc: baseUser("prova-test", "prova@test.it", "Pia", "Prova", "User", {
        tipologiaIscrizione: "ABBONAMENTO_PROVA",
        entrateDisponibili: 1,
      }),
    },
    {
      // Nuovo modello: abbonamenti via collezione+snapshot (sotto).
      uid: "abbonato-test",
      email: "abbonato@test.it",
      doc: baseUser("abbonato-test", "abbonato@test.it", "Alba", "Abbonata", "User", {
        tipologiaCorsoTags: [],
      }),
    },
  ];

  for (const u of users) {
    await createAuthUser(u.uid, u.email, `${u.doc.name} ${u.doc.lastName}`);
    await db.collection("users").doc(u.uid).set(u.doc);
    console.log(`  ${u.email} (${u.doc.role})`);
  }

  // Abbonamenti nuovo modello per abbonato-test: Open 3x + Hyrox 10 ingressi.
  // Riusa il catalogo/logica compilati (stesse chiavi e date di produzione).
  console.log("Abbonamenti (collezione subscriptions + snapshot)…");
  const snapshot = [];
  for (const planKey of ["open_3x_3m", "hyrox_10i_3m"]) {
    const plan = planByKey(planKey);
    if (!plan) throw new Error(`piano sconosciuto nel catalogo: ${planKey}`);
    const record = buildSubscriptionFromPlan(plan, Date.now() - 86400000);
    const ref = db.collection("subscriptions").doc();
    // Stessa shape di assignSubscription (recordToDoc dal compilato).
    await ref.set(recordToDoc(record, "abbonato-test", "seed"));
    snapshot.push(recordToSnapshotEntry({ ...record, id: ref.id }));
    console.log(`  ${planKey} → ${ref.id}`);
  }
  await db
    .collection("users")
    .doc("abbonato-test")
    .set({ activeSubscriptions: snapshot }, { merge: true });

  // Corsi: settimana prossima (lun-sab), tutte le tipologie + casi limite.
  console.log("Corsi…");
  const courses = [
    course("open-lun", "Open mattina", ["Open"], nextWeekDayAt(9), 10, 0),
    course("open-mer", "Open sera", ["Open"], nextWeekDayAt(19, 2), 10, 0),
    course("open-ven", "Open pranzo", ["Open"], nextWeekDayAt(13, 4), 10, 0),
    // Pieno con un posto in waitlist già occupato: per testare CAN_WAITLIST.
    // NB: i contatori subscribed dei corsi "pieni" sono volutamente sintetici
    // (nessun utente seed è iscritto): bastano per gli stati FULL/CAN_WAITLIST;
    // le viste partecipanti/"Correggi conteggio" li vedrebbero senza iscritti.
    course("open-pieno", "Open PIENO", ["Open"], nextWeekDayAt(18, 1), 2, 2, {
      waitlist: ["mensile-test"],
    }),
    course("hyrox-mar", "Hyrox", ["Hyrox"], nextWeekDayAt(18, 1), 8, 0),
    course("hyrox-gio", "Hyrox avanzato", ["Hyrox"], nextWeekDayAt(18, 3), 8, 0),
    course("pt-mer", "Personal Training", ["Personal Trainer"], nextWeekDayAt(15, 2), 1, 0),
    course("heymamma-sab", "Hey Mamma", ["Hey Mamma"], nextWeekDayAt(10, 5), 12, 0),
    // Flag spenti: per testare i gate reminder/waitlist.
    course("open-no-waitlist", "Open senza lista d'attesa", ["Open"], nextWeekDayAt(7, 3), 1, 1, {
      waitlistEnabled: false,
    }),
    course("open-no-reminder", "Open senza promemoria", ["Open"], nextWeekDayAt(8, 4), 10, 0, {
      reminderEnabled: false,
    }),
  ];
  // L'utente in waitlist deve avere il corso anche in waitlistCourses.
  await db
    .collection("users")
    .doc("mensile-test")
    .set({ waitlistCourses: ["open-pieno"] }, { merge: true });

  for (const c of courses) {
    await db.collection("courses").doc(c.uid).set(c);
    console.log(`  ${c.uid} (${c.tags.join(",")}) ${c.subscribed}/${c.capacity}`);
  }

  console.log("\nSeed completato. Emulator UI: http://localhost:4000");
  console.log("Login app: admin@test.it / pacchetto@test.it / mensile@test.it /");
  console.log("           prova@test.it / abbonato@test.it — password: %s", PASSWORD);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("Seed fallito:", e);
    process.exit(1);
  });
