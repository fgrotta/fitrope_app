import { mkdtempSync, readFileSync, statSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { csvContent, writePrivateCsv } from "../migration/csv";

describe("migration CSV", () => {
  test("usa BOM, separatore ; ed escaping RFC 4180", () => {
    const content = csvContent(
      ["plain", "special", "unicode", "list"],
      [{
        plain: "ok",
        special: "riga; con \"virgolette\"\ne newline",
        unicode: "Giulia È",
        list: ["Open", "Yoga"],
      }]
    );
    expect(content.startsWith("\uFEFFplain;special;unicode;list\r\n")).toBe(true);
    expect(content).toContain('"riga; con ""virgolette""\ne newline"');
    expect(content).toContain('"[""Open"",""Yoga""]"');
    expect(content).toContain("Giulia È");
  });

  test("scrive il report con permessi 0600", () => {
    const dir = mkdtempSync(join(tmpdir(), "fitrope-migration-"));
    const file = join(dir, "report.csv");
    writePrivateCsv(file, ["email"], [{ email: "private@example.com" }]);
    expect(statSync(file).mode & 0o777).toBe(0o600);
    expect(readFileSync(file, "utf8")).toContain("private@example.com");
  });
});

