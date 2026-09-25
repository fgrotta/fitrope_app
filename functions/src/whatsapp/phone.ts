// Normalizzazione di `users/{uid}.numeroTelefono` verso E.164 per il webhook Make.
//
// Il dato di norma è pulito (le schermate validano 10 cifre, provisioning.ts fa
// solo trim()), ma record creati da console, import o versioni precedenti
// possono contenere separatori, prefissi internazionali, fissi o due numeri.

export interface NormalizedPhone {
  /** Numero in formato E.164 (con il `+`), o `null` se non utilizzabile. */
  e164: string | null;
  /** Sole cifre, senza `+`. */
  digits: string | null;
  /** `false` se il numero non è (probabilmente) raggiungibile su WhatsApp. */
  likelyMobile: boolean;
  /** Motivo dello scarto, per i log. */
  reason?: "empty" | "placeholder" | "not_numeric" | "too_short" | "too_long";
}

const E164_MIN = 8;
const E164_MAX = 15;
const IT_NATIONAL_MIN = 6;
const IT_NATIONAL_MAX = 11;

export function normalizePhoneE164(raw: string | null | undefined): NormalizedPhone {
  const nope = (reason: NonNullable<NormalizedPhone["reason"]>): NormalizedPhone => ({
    e164: null,
    digits: null,
    likelyMobile: false,
    reason,
  });

  if (raw === null || raw === undefined) return nope("empty");
  // \s non copre l'NBSP in tutte le versioni di JS: lo normalizzo a mano.
  const trimmed = raw.replace(/\u00a0/g, " ").trim();
  if (trimmed === "") return nope("empty");
  // '-' è il placeholder usato nei campi anagrafici mancanti.
  if (trimmed === "-") return nope("placeholder");

  const hasPlus = trimmed.startsWith("+");
  let digits = trimmed.replace(/\D/g, "");
  if (digits === "") return nope("not_numeric");

  // Prefisso internazionale scritto come 00 anziché +.
  let international = hasPlus;
  if (!international && digits.startsWith("00") && digits.length >= 12) {
    digits = digits.slice(2);
    international = true;
  }

  if (international) {
    if (digits.length < E164_MIN) return nope("too_short");
    if (digits.length > E164_MAX) return nope("too_long");
    const national = digits.startsWith("39") ? digits.slice(2) : null;
    return {
      e164: `+${digits}`,
      digits,
      // Fuori dall'Italia il prefisso non dice se è un cellulare: meglio provare
      // che scartare in silenzio un destinatario valido.
      likelyMobile: national === null ? true : isItalianMobile(national),
    };
  }

  // Un `39` iniziale su 10 cifre NON è il prefisso paese ma l'inizio del numero
  // (es. 3931234567): lo tolgo solo da 12 cifre in su.
  const national =
    digits.startsWith("39") && digits.length >= 12 ? digits.slice(2) : digits;
  if (national.length < IT_NATIONAL_MIN) return nope("too_short");
  if (national.length > IT_NATIONAL_MAX) return nope("too_long");

  const full = `39${national}`;
  return { e164: `+${full}`, digits: full, likelyMobile: isItalianMobile(national) };
}

/** I cellulari italiani iniziano per 3 e hanno 9 o 10 cifre. */
function isItalianMobile(national: string): boolean {
  return national.startsWith("3") && national.length >= 9 && national.length <= 10;
}
