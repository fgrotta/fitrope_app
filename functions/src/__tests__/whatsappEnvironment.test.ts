import { isWhatsappRecipientAllowed, whatsappDemoMode } from "../whatsapp/environment";

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
