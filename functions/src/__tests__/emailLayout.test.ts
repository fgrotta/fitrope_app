import { readdirSync, readFileSync } from "fs";
import * as path from "path";
import { emailShell, ctaButton, escapeHtml, APP_URL, LOGO_URL } from "../email/layout";
import {
  trialConfirmationBody, trialReminderBody, waitlistSpotAvailableBody,
  trialConfirmationSubject, trialReminderSubject, waitlistSpotAvailableSubject,
} from "../enrollment/emailTemplates";
import { certificateReminderBody, certificateExpiryTodayBody } from "../certificateEmailTemplates";

const args = {
  courseName: 'Pilates <b> & "Yoga"', courseDate: "Giovedì 10 Aprile", courseTime: "09:00 - 10:00",
  sala: "Sala <2>", googleUrl: "https://calendar.google.com/calendar/render?action=TEMPLATE&text=Pilates",
  icsUrl: "https://example.test/courseIcs?courseId=c1&x=1",
};

test("escapeHtml protegge testo e attributi", () => {
  expect(escapeHtml(`a&b<c>"d'`)).toBe("a&amp;b&lt;c&gt;&quot;d&#39;");
  expect(ctaButton('Apri "Fit"', 'https://example.it/?a=1&b="2"'))
    .toContain('href="https://example.it/?a=1&amp;b=&quot;2&quot;"');
  expect(ctaButton("Apri")).toContain(`href="${APP_URL}"`);
});

test("titolo e nota sono escapati; il corpo preserva il markup", () => {
  const html = emailShell({ title: "Titolo <x>", bodyHtml: "<p>corpo</p>", footerNote: "Nota <b>" });
  expect(html).toContain("Titolo &lt;x&gt;");
  expect(html).toContain("<p>corpo</p>");
  expect(html).toContain("Nota &lt;b&gt;");
  expect(emailShell({ title: "t", bodyHtml: "" })).not.toContain("footer-note");
});

test.each([
  trialConfirmationBody(args), trialReminderBody(args),
  waitlistSpotAvailableBody({ ...args, spotsAvailable: 1 }),
  certificateReminderBody("Mario"), certificateExpiryTodayBody("Mario"),
])("ogni template usa il documento e il brand comuni", (html) => {
  expect(html).toContain('<html lang="it">');
  expect(html).toContain('<meta charset="utf-8" />');
  expect(html).toContain(`src="${LOGO_URL}"`);
  expect(html).toContain('alt="Fit House"');
  expect(html).toContain("— Il team Fit House");
  expect(html.match(/<html[\s>]/g)).toHaveLength(1);
  expect(html).toContain("</html>");
});

test.each([trialConfirmationBody, trialReminderBody])("prova: dettagli, sala e link calendario preservati", (body) => {
  const html = body(args);
  expect(html).toContain("Pilates &lt;b&gt; &amp; &quot;Yoga&quot;");
  expect(html).not.toContain(args.courseName);
  expect(html).toContain(args.courseDate);
  expect(html).toContain(args.courseTime);
  expect(html).toContain("Sala &lt;2&gt;");
  expect(html).toContain("Aggiungi a Google Calendar");
  expect(html).toContain("Apple / Outlook / altro");
  expect(html).toContain('href="https://calendar.google.com/calendar/render?action=TEMPLATE&amp;text=Pilates"');
  expect(html).toContain('href="https://example.test/courseIcs?courseId=c1&amp;x=1"');
  expect(body({ ...args, sala: "  " })).not.toContain("<strong>Sala:</strong>");
});

test("waitlist: singolare, plurale e dettagli preservati", () => {
  const one = waitlistSpotAvailableBody({ ...args, spotsAvailable: 1 });
  expect(one).toContain("1 posto disponibile");
  expect(one).not.toContain("posti disponibili");
  expect(one).toContain(args.courseDate);
  expect(one).toContain(args.courseTime);
  expect(one).toContain("Pilates &lt;b&gt; &amp; &quot;Yoga&quot;");
  expect(waitlistSpotAvailableBody({ ...args, spotsAvailable: 3 })).toContain("3 posti disponibili");
});

test("oggetti email enrollment invariati", () => {
  expect(trialConfirmationSubject("Pilates")).toBe('Iscrizione confermata: lezione di prova "Pilates"');
  expect(trialReminderSubject("Pilates")).toBe('Promemoria: la tua lezione di prova "Pilates" è domani!');
  expect(waitlistSpotAvailableSubject("Pilates")).toBe('Posto disponibile nel corso "Pilates"!');
});

test("certificati: nomi escapati senza doppio escaping", () => {
  const html = certificateReminderBody("Luca <script> & O'Neil");
  expect(html).toContain("Luca &lt;script&gt; &amp; O&#39;Neil");
  expect(html).not.toContain("&amp;lt;");
  expect(html).not.toContain("<script>");
});

test("un solo modulo può definire il documento HTML", () => {
  const src = path.join(__dirname, "..");
  const offenders: string[] = [];
  function walk(dir: string): void {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const file = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (!["__tests__", "__integration__"].includes(e.name)) walk(file);
      } else if (e.name.endsWith(".ts") && file !== path.join(src, "email", "layout.ts") &&
                 /<html[\s>]/.test(readFileSync(file, "utf8"))) {
        offenders.push(path.relative(src, file));
      }
    }
  }
  walk(src);
  expect(offenders).toEqual([]);
});
