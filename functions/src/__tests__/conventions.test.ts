import * as fs from "fs";
import * as path from "path";

// Guard di convenzione (lezione dello smoke test PR4.5, vedi
// docs/AMBIENTI_DI_TEST.md): il runtime dell'emulatore functions monkey-patcha
// firebase-admin e il namespace `admin.firestore` PERDE le proprietà statiche
// (Timestamp, FieldValue) → il codice runtime deve usare gli import modulari
// `import { Timestamp, FieldValue } from "firebase-admin/firestore"`.
// Un uso namespace passerebbe tsc e tutti i test Jest (runtime non patchato) e
// si romperebbe solo sull'emulatore/QA manuale: questo test lo blocca in CI.
//
// NB: gli alias di TIPO (admin.firestore.DocumentData, .Firestore, ecc.) sono
// innocui (compile-time only) e restano consentiti.

const SRC_DIR = path.join(__dirname, "..");
const FORBIDDEN = /admin\.firestore\.(Timestamp|FieldValue)/;

function tsFilesUnder(dir: string): string[] {
  const out: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === "__tests__" || entry.name === "node_modules") continue;
      out.push(...tsFilesUnder(full));
    } else if (entry.name.endsWith(".ts")) {
      out.push(full);
    }
  }
  return out;
}

describe("convenzioni codebase functions", () => {
  test("nessun uso runtime di admin.firestore.Timestamp/FieldValue in src (usare firebase-admin/firestore)", () => {
    const offenders: string[] = [];
    for (const file of tsFilesUnder(SRC_DIR)) {
      const lines = fs.readFileSync(file, "utf8").split("\n");
      lines.forEach((line, i) => {
        if (FORBIDDEN.test(line)) {
          offenders.push(`${path.relative(SRC_DIR, file)}:${i + 1}: ${line.trim()}`);
        }
      });
    }
    expect(offenders).toEqual([]);
  });
});
