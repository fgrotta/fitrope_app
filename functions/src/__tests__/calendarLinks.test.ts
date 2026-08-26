import {
  GYM_ADDRESS,
  calendarButtonsHtml,
  eventLocation,
  formatUtcStamp,
  googleCalendarUrl,
  htmlAttr,
  icsBaseUrl,
  icsUrl,
} from "../enrollment/calendarLinks";

describe("formatUtcStamp", () => {
  test("produce il formato basic UTC di RFC 5545", () => {
    expect(formatUtcStamp(Date.UTC(2026, 0, 5, 8, 30, 0))).toBe("20260105T083000Z");
  });

  test("resta assoluto in ora legale (nessuna conversione al fuso locale)", () => {
    // 10:00 Rome d'estate = 08:00Z; il timbro deve essere 08:00Z, non 10:00.
    expect(formatUtcStamp(Date.UTC(2026, 6, 10, 8, 0, 0))).toBe("20260710T080000Z");
    // 10:00 Rome d'inverno = 09:00Z.
    expect(formatUtcStamp(Date.UTC(2026, 0, 10, 9, 0, 0))).toBe("20260110T090000Z");
  });

  test("zero-padding su mese, giorno e ora", () => {
    expect(formatUtcStamp(Date.UTC(2026, 8, 9, 7, 5, 4))).toBe("20260909T070504Z");
  });
});

describe("eventLocation", () => {
  test("sala valorizzata: sala + indirizzo", () => {
    expect(eventLocation("Sala 2")).toBe(`Sala 2 — ${GYM_ADDRESS}`);
  });

  test("sala assente, vuota o soli spazi: solo indirizzo", () => {
    expect(eventLocation(null)).toBe(GYM_ADDRESS);
    expect(eventLocation(undefined)).toBe(GYM_ADDRESS);
    expect(eventLocation("   ")).toBe(GYM_ADDRESS);
  });
});

describe("googleCalendarUrl", () => {
  const args = {
    courseName: "Hey Mamma, sala 2",
    startMillis: Date.UTC(2026, 6, 10, 8, 0),
    endMillis: Date.UTC(2026, 6, 10, 9, 0),
    sala: "Sala 2",
  };

  test("contiene action, text, dates e location", () => {
    const url = googleCalendarUrl(args);
    expect(url.startsWith("https://calendar.google.com/calendar/render?")).toBe(true);
    expect(url).toContain("action=TEMPLATE");
    expect(url).toContain("20260710T080000Z%2F20260710T090000Z");
    const parsed = new URL(url);
    expect(parsed.searchParams.get("text")).toBe("Hey Mamma, sala 2");
    expect(parsed.searchParams.get("location")).toBe(`Sala 2 — ${GYM_ADDRESS}`);
  });

  test("percent-encoding di & e accenti nel nome corso", () => {
    const url = googleCalendarUrl({ ...args, courseName: "Body & Mind à 2" });
    // L'& del nome NON deve creare un parametro nuovo.
    expect(new URL(url).searchParams.get("text")).toBe("Body & Mind à 2");
    expect(url).toContain("Body+%26+Mind");
  });
});

describe("htmlAttr", () => {
  test("trasforma gli & in &amp; per l'uso in href", () => {
    expect(htmlAttr("https://x/y?a=1&b=2&c=3")).toBe("https://x/y?a=1&amp;b=2&amp;c=3");
  });

  test("non tocca un URL senza &", () => {
    expect(htmlAttr("https://x/y?a=1")).toBe("https://x/y?a=1");
  });
});

describe("icsBaseUrl / icsUrl", () => {
  const saved = {
    override: process.env.CALENDAR_ICS_BASE_URL,
    emulator: process.env.FUNCTIONS_EMULATOR,
    project: process.env.GCLOUD_PROJECT,
  };

  function restore(key: keyof typeof saved, envName: string) {
    if (saved[key] === undefined) delete process.env[envName];
    else process.env[envName] = saved[key] as string;
  }

  afterEach(() => {
    restore("override", "CALENDAR_ICS_BASE_URL");
    restore("emulator", "FUNCTIONS_EMULATOR");
    restore("project", "GCLOUD_PROJECT");
  });

  test("override esplicito vince su tutto", () => {
    process.env.CALENDAR_ICS_BASE_URL = "https://cal.example.com/ics";
    process.env.FUNCTIONS_EMULATOR = "true";
    expect(icsBaseUrl()).toBe("https://cal.example.com/ics");
  });

  test("emulatore: host locale con project e regione", () => {
    delete process.env.CALENDAR_ICS_BASE_URL;
    process.env.FUNCTIONS_EMULATOR = "true";
    process.env.GCLOUD_PROJECT = "fit-rope-app-1f575";
    expect(icsBaseUrl()).toBe(
      "http://127.0.0.1:5001/fit-rope-app-1f575/europe-west8/courseIcs"
    );
  });

  test("deployato: host cloudfunctions della regione del progetto", () => {
    delete process.env.CALENDAR_ICS_BASE_URL;
    delete process.env.FUNCTIONS_EMULATOR;
    process.env.GCLOUD_PROJECT = "fit-rope-staging";
    expect(icsBaseUrl()).toBe(
      "https://europe-west8-fit-rope-staging.cloudfunctions.net/courseIcs"
    );
  });

  test("icsUrl encoda il courseId", () => {
    process.env.CALENDAR_ICS_BASE_URL = "https://cal.example.com/ics";
    expect(icsUrl("a b/c")).toBe("https://cal.example.com/ics?courseId=a%20b%2Fc");
  });
});

describe("calendarButtonsHtml", () => {
  test("due bottoni con href escaped", () => {
    const html = calendarButtonsHtml({
      googleUrl: "https://g/r?a=1&b=2",
      icsUrl: "https://f/courseIcs?courseId=c1",
    });
    expect(html).toContain('href="https://g/r?a=1&amp;b=2"');
    expect(html).toContain('href="https://f/courseIcs?courseId=c1"');
    expect(html).toContain("Aggiungi a Google Calendar");
    expect(html).toContain("Apple / Outlook / altro");
    // Bottoni su <td> e non <div>: Outlook ignora il border-radius sui div.
    expect(html).not.toContain("<div");
  });
});
