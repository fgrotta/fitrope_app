import {
  isWhatsappRecipientAllowed,
  readMetaSettings,
  whatsappDemoMode,
  whatsappTransportName,
} from "../whatsapp/environment";

describe("whatsappDemoMode", () => {
  test.each([
    [undefined, "off"],
    ["", "off"],
    ["off", "off"],
    ["si", "off"],
    ["test", "test"],
    ["live", "live"],
    [" LIVE ", "live"],
  ])("WHATSAPP_DEMO_MODE=%p → %s", (raw, expected) => {
    const env: NodeJS.ProcessEnv = raw === undefined ? {} : { WHATSAPP_DEMO_MODE: raw };
    expect(whatsappDemoMode(env)).toBe(expected);
  });
});

describe("isWhatsappRecipientAllowed", () => {
  test("fuori da staging ogni numero è ammesso", () => {
    expect(isWhatsappRecipientAllowed("+393331234567", {})).toBe(true);
  });

  test("su staging senza allowlist non passa nessuno", () => {
    expect(isWhatsappRecipientAllowed("+393331234567", { APP_ENV: "staging" })).toBe(false);
  });

  test("sull'emulatore senza allowlist non passa nessuno (carica la modalità di produzione)", () => {
    expect(isWhatsappRecipientAllowed("+393331234567", { FUNCTIONS_EMULATOR: "true" })).toBe(false);
    expect(
      isWhatsappRecipientAllowed("+393331234567", {
        FUNCTIONS_EMULATOR: "true",
        STAGING_WHATSAPP_ALLOWLIST: "3331234567",
      })
    ).toBe(true);
  });

  test("su staging passa solo chi è in allowlist, anche se scritto senza prefisso", () => {
    const env = {
      APP_ENV: "staging",
      STAGING_WHATSAPP_ALLOWLIST: " 333 123 4567 , +41791234567 ",
    };
    expect(isWhatsappRecipientAllowed("+393331234567", env)).toBe(true);
    expect(isWhatsappRecipientAllowed("+41791234567", env)).toBe(true);
    expect(isWhatsappRecipientAllowed("+393339876543", env)).toBe(false);
  });
});

describe("whatsappTransportName", () => {
  test.each([
    [undefined, "make"],
    ["", "make"],
    ["make", "make"],
    [" META ", "meta"],
  ])("WHATSAPP_TRANSPORT=%p → %s", (raw, expected) => {
    const env: NodeJS.ProcessEnv = raw === undefined ? {} : { WHATSAPP_TRANSPORT: raw };
    expect(whatsappTransportName(env)).toBe(expected);
  });

  test("un valore sconosciuto fa fallire la discovery invece di scegliere a caso", () => {
    expect(() => whatsappTransportName({ WHATSAPP_TRANSPORT: "twilio" })).toThrow(/WHATSAPP_TRANSPORT/);
  });
});

describe("readMetaSettings", () => {
  const env = {
    META_GRAPH_VERSION: "v26.0",
    META_WA_PHONE_NUMBER_ID: "106540352242922",
    META_WA_TEMPLATE_REMINDER: "promemoria_lezione_prova",
  };

  test("legge versione, numero e template; lingua it di default; conferma assente", () => {
    expect(readMetaSettings(env)).toEqual({
      graphVersion: "v26.0",
      phoneNumberId: "106540352242922",
      templates: { reminder: { name: "promemoria_lezione_prova", lang: "it" } },
    });
  });

  test("template di conferma opzionale e lingua configurabile", () => {
    expect(
      readMetaSettings({
        ...env,
        META_WA_TEMPLATE_LANG: " it ",
        META_WA_TEMPLATE_BOOKED: "conferma_lezione_prova",
      }).templates
    ).toEqual({
      reminder: { name: "promemoria_lezione_prova", lang: "it" },
      booked: { name: "conferma_lezione_prova", lang: "it" },
    });
  });

  test.each([
    ["META_GRAPH_VERSION", { META_GRAPH_VERSION: undefined }],
    ["META_GRAPH_VERSION", { META_GRAPH_VERSION: "26" }],
    ["META_WA_PHONE_NUMBER_ID", { META_WA_PHONE_NUMBER_ID: "" }],
    ["META_WA_PHONE_NUMBER_ID", { META_WA_PHONE_NUMBER_ID: "+39 333 1234567" }],
    ["META_WA_TEMPLATE_REMINDER", { META_WA_TEMPLATE_REMINDER: " " }],
  ])("fallisce in discovery se %s manca o non è valida", (key, over) => {
    expect(() => readMetaSettings({ ...env, ...over })).toThrow(new RegExp(key));
  });
});
