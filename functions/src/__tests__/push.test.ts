import {
  appBaseUrl,
  pushLaunchUrl,
  buildPushPayload,
  sendPush,
} from "../push";
import { ONESIGNAL_APP_ID } from "../handler";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

const ENV_KEYS = ["APP_BASE_URL", "GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT"] as const;
const original: Record<string, string | undefined> = {};

beforeEach(() => {
  for (const key of ENV_KEYS) {
    original[key] = process.env[key];
    delete process.env[key];
  }
});

afterEach(() => {
  for (const key of ENV_KEYS) {
    if (original[key] === undefined) delete process.env[key];
    else process.env[key] = original[key];
  }
  jest.clearAllMocks();
});

describe("appBaseUrl", () => {
  test("mappa il progetto di produzione", () => {
    process.env.GCLOUD_PROJECT = "fit-rope-app-1f575";
    expect(appBaseUrl()).toBe("https://app.fithousemonza.it/");
  });

  test("mappa il progetto di staging sul sito Pages", () => {
    process.env.GCLOUD_PROJECT = "fit-rope-staging";
    expect(appBaseUrl()).toBe("https://fgrotta.github.io/fitrope_app/");
  });

  test("un progetto sconosciuto ricade su produzione", () => {
    process.env.GCLOUD_PROJECT = "demo-qualcosa";
    expect(appBaseUrl()).toBe("https://app.fithousemonza.it/");
  });

  test("APP_BASE_URL vince e viene normalizzata con lo slash finale", () => {
    process.env.GCLOUD_PROJECT = "fit-rope-staging";
    process.env.APP_BASE_URL = "https://esempio.it/app";
    expect(appBaseUrl()).toBe("https://esempio.it/app/");
  });
});

describe("pushLaunchUrl", () => {
  test("punta alla root: un fragment avrebbe la precedenza su initialRoute", () => {
    process.env.GCLOUD_PROJECT = "fit-rope-app-1f575";
    expect(pushLaunchUrl()).toBe("https://app.fithousemonza.it/");
    expect(pushLaunchUrl("waitlist_spot")).toBe(
      "https://app.fithousemonza.it/?src=waitlist_spot"
    );
    expect(pushLaunchUrl()).not.toContain("#");
  });
});

describe("buildPushPayload", () => {
  test("canale push, app_id iniettato, deeplink in web_url", () => {
    process.env.GCLOUD_PROJECT = "fit-rope-app-1f575";
    const payload = buildPushPayload({
      externalIds: ["u1", "u2"],
      heading: "Titolo",
      content: "Corpo",
      source: "waitlist_spot",
    });

    expect(payload.target_channel).toBe("push");
    expect(payload.app_id).toBe(ONESIGNAL_APP_ID);
    expect(payload.include_aliases).toEqual({ external_id: ["u1", "u2"] });
    // `web_url` e non `url`/`app_url`: l'app Flutter non registra uno schema custom.
    expect(payload.web_url).toBe("https://app.fithousemonza.it/?src=waitlist_spot");
    expect(payload.url).toBeUndefined();
  });

  test("senza traduzione inglese ripete l'italiano", () => {
    const payload = buildPushPayload({
      externalIds: ["u1"],
      heading: "Titolo",
      content: "Corpo",
    });
    expect(payload.headings).toEqual({ it: "Titolo", en: "Titolo" });
    expect(payload.contents).toEqual({ it: "Corpo", en: "Corpo" });
  });

  test("i campi opzionali compaiono solo se valorizzati", () => {
    const minimal = buildPushPayload({
      externalIds: ["u1"],
      heading: "T",
      content: "C",
    });
    expect(minimal.send_after).toBeUndefined();
    expect(minimal.ttl).toBeUndefined();
    expect(minimal.collapse_id).toBeUndefined();

    const full = buildPushPayload({
      externalIds: ["u1"],
      heading: "T",
      content: "C",
      sendAfter: "2026-06-09T17:00:00.000Z",
      ttlSeconds: 3600,
      collapseId: "c1",
    });
    expect(full.send_after).toBe("2026-06-09T17:00:00.000Z");
    expect(full.ttl).toBe(3600);
    expect(full.collapse_id).toBe("c1");
  });
});

describe("sendPush", () => {
  test("un errore OneSignal non propaga: l'invio e' best-effort", async () => {
    const fetchMock = jest.fn().mockRejectedValue(new Error("network down"));
    global.fetch = fetchMock as unknown as typeof fetch;

    await expect(
      sendPush("key", "Test", { externalIds: ["u1"], heading: "T", content: "C" })
    ).resolves.toBeUndefined();
  });
});
