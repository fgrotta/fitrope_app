import { normalizePhoneE164 } from "../whatsapp/phone";

describe("normalizePhoneE164", () => {
  test.each([
    ["null", null],
    ["undefined", undefined],
    ["stringa vuota", ""],
    ["soli spazi", "   "],
  ])("scarta %s con reason empty", (_label, input) => {
    expect(normalizePhoneE164(input)).toMatchObject({ e164: null, reason: "empty" });
  });

  test("riconosce il placeholder '-'", () => {
    expect(normalizePhoneE164("-")).toMatchObject({ e164: null, reason: "placeholder" });
  });

  test("scarta il testo non numerico", () => {
    expect(normalizePhoneE164("n/d")).toMatchObject({ e164: null, reason: "not_numeric" });
  });

  test.each([
    ["spazi", "333 123 4567"],
    ["trattini e punti", "333-123.4567"],
    ["parentesi", "(333) 1234567"],
    ["NBSP", "333\u00a01234567"],
  ])("rimuove i separatori (%s)", (_label, input) => {
    expect(normalizePhoneE164(input)).toEqual({
      e164: "+393331234567",
      digits: "393331234567",
      likelyMobile: true,
    });
  });

  test("accetta un cellulare a 9 cifre", () => {
    expect(normalizePhoneE164("335123456")).toMatchObject({
      e164: "+39335123456",
      likelyMobile: true,
    });
  });

  test("lascia invariato un numero già internazionale", () => {
    expect(normalizePhoneE164("+393331234567")).toMatchObject({
      e164: "+393331234567",
      likelyMobile: true,
    });
  });

  test("converte il prefisso 00 in +", () => {
    expect(normalizePhoneE164("00393331234567")).toMatchObject({ e164: "+393331234567" });
  });

  test("NON tratta un 39 iniziale su 10 cifre come prefisso paese", () => {
    expect(normalizePhoneE164("3931234567")).toMatchObject({
      e164: "+393931234567",
      likelyMobile: true,
    });
  });

  test("preserva un numero estero senza forzare il +39", () => {
    expect(normalizePhoneE164("+41791234567")).toMatchObject({
      e164: "+41791234567",
      likelyMobile: true,
    });
  });

  test("marca un fisso come non mobile", () => {
    expect(normalizePhoneE164("0392123456")).toMatchObject({
      e164: "+390392123456",
      likelyMobile: false,
    });
  });

  test("scarta due numeri nello stesso campo", () => {
    expect(normalizePhoneE164("3331234567 / 3339876543")).toMatchObject({
      e164: null,
      reason: "too_long",
    });
  });

  test("scarta un numero troppo corto", () => {
    expect(normalizePhoneE164("+39")).toMatchObject({ e164: null, reason: "too_short" });
    expect(normalizePhoneE164("12345")).toMatchObject({ e164: null, reason: "too_short" });
  });
});
