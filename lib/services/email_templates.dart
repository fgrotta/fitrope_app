/// URL pubblico del logo usato nelle email.
/// Hostato sul dominio Firebase Hosting (le email OneSignal caricano immagini
/// via HTTP, quindi servono asset pubblici — gli asset Flutter locali non
/// sarebbero accessibili).
const String _logoUrl =
    'https://app.fithousemonza.it/assets/assets/new_logo_only.png';

String _emailHeader(String title) {
  return '''
          <!-- Header con logo -->
          <tr>
            <td style="background-color: #6077F6; padding: 24px 30px; text-align: center;">
              <img src="$_logoUrl" alt="Fit House" width="72"
                   style="display: block; margin: 0 auto 12px auto; border: 0; height: auto;" />
              <h1 style="color: #ffffff; margin: 0; font-size: 22px; font-weight: 600;">
                $title
              </h1>
            </td>
          </tr>''';
}

String _emailCta(String label) {
  return '''
              <table cellpadding="0" cellspacing="0" style="margin: 20px 0;">
                <tr>
                  <td style="background-color: #6077F6; border-radius: 8px;">
                    <a href="https://app.fithousemonza.it/" target="_blank"
                       style="display: inline-block; padding: 12px 24px; color: #ffffff; font-size: 15px; font-weight: 600; text-decoration: none;">
                      $label
                    </a>
                  </td>
                </tr>
              </table>''';
}

/// Escaping di un URL per l'uso in un attributo HTML: gli `&` dei query string
/// vanno scritti `&amp;`, altrimenti i client email piu' severi troncano l'href.
String htmlAttrUrl(String url) => url.replaceAll('&', '&amp;');

/// Blocco con i due bottoni "aggiungi al calendario".
/// Mirror di `calendarButtonsHtml` in functions/src/enrollment/calendarLinks.ts.
String _calendarButtons({required String googleUrl, required String icsUrl}) {
  return '''
              <!-- Aggiungi al calendario -->
              <table cellpadding="0" cellspacing="0" style="margin: 20px 0;">
                <tr>
                  <td style="background-color: #6077F6; border-radius: 8px;">
                    <a href="${htmlAttrUrl(googleUrl)}" target="_blank"
                       style="display: inline-block; padding: 12px 20px; color: #ffffff; font-size: 15px; font-weight: 600; text-decoration: none;">
                      📅 Aggiungi a Google Calendar
                    </a>
                  </td>
                  <td style="width: 12px;">&nbsp;</td>
                  <td style="border: 1px solid #6077F6; border-radius: 8px;">
                    <a href="${htmlAttrUrl(icsUrl)}" target="_blank"
                       style="display: inline-block; padding: 12px 20px; color: #6077F6; font-size: 15px; font-weight: 600; text-decoration: none;">
                      🍎 Apple / Outlook / altro
                    </a>
                  </td>
                </tr>
              </table>''';
}

/// Riga "sala" della card dettagli: presente solo se il corso ha una sala.
String _salaRow(String? sala) {
  final trimmed = sala?.trim();
  if (trimmed == null || trimmed.isEmpty) return '';
  return '''

                    <p style="margin: 4px 0 0 0; font-size: 14px; color: #555555;">
                      📍 <strong>Sala:</strong> $trimmed
                    </p>''';
}

String _emailFooter() {
  return '''
          <!-- Footer -->
          <tr>
            <td style="background-color: #f9f9f9; padding: 20px; text-align: center; border-top: 1px solid #eeeeee;">
              <p style="color: #999999; font-size: 12px; margin: 0;">
                — Il team Fit House
              </p>
            </td>
          </tr>''';
}

String trialConfirmationSubject(String courseName) {
  return 'Iscrizione confermata: lezione di prova "$courseName"';
}

String trialConfirmationBody({
  required String courseName,
  required String courseDate,
  required String courseTime,
  required String googleUrl,
  required String icsUrl,
  String? sala,
}) {
  return '''
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
</head>
<body style="margin: 0; padding: 0; background-color: #f4f4f4; font-family: Arial, sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f4f4f4; padding: 40px 0;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden;">

${_emailHeader('Iscrizione confermata')}

          <!-- Body -->
          <tr>
            <td style="padding: 30px;">
              <p style="color: #333333; font-size: 16px; line-height: 1.6; margin-top: 0;">
                Ciao,
              </p>
              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                La tua iscrizione alla lezione di prova è confermata. Ti aspettiamo 💪
              </p>

              <!-- Course details card -->
              <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f0f2ff; border-radius: 8px; margin: 20px 0;">
                <tr>
                  <td style="padding: 20px;">
                    <p style="margin: 0 0 8px 0; font-size: 18px; font-weight: bold; color: #333333;">
                      $courseName
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 14px; color: #555555;">
                      📅 <strong>Data:</strong> $courseDate
                    </p>
                    <p style="margin: 0; font-size: 14px; color: #555555;">
                      🕐 <strong>Orario:</strong> $courseTime
                    </p>${_salaRow(sala)}
                  </td>
                </tr>
              </table>

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Segna la lezione sul tuo calendario così non te la dimentichi:
              </p>

${_calendarButtons(googleUrl: googleUrl, icsUrl: icsUrl)}

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Ricordati di portare abbigliamento comodo e una bottiglietta d'acqua.
              </p>

${_emailCta('Apri Fit House')}

            </td>
          </tr>

${_emailFooter()}

        </table>
      </td>
    </tr>
  </table>
</body>
</html>''';
}

String trialReminderSubject(String courseName) {
  return 'Promemoria: la tua lezione di prova "$courseName" è domani!';
}

String trialReminderBody({
  required String courseName,
  required String courseDate,
  required String courseTime,
  required String googleUrl,
  required String icsUrl,
  String? sala,
}) {
  return '''
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
</head>
<body style="margin: 0; padding: 0; background-color: #f4f4f4; font-family: Arial, sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f4f4f4; padding: 40px 0;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden;">

${_emailHeader('Promemoria lezione di prova')}

          <!-- Body -->
          <tr>
            <td style="padding: 30px;">
              <p style="color: #333333; font-size: 16px; line-height: 1.6; margin-top: 0;">
                Ciao,
              </p>
              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Ti ricordiamo che domani hai la tua lezione di prova! Ti aspettiamo 💪
              </p>

              <!-- Course details card -->
              <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f0f2ff; border-radius: 8px; margin: 20px 0;">
                <tr>
                  <td style="padding: 20px;">
                    <p style="margin: 0 0 8px 0; font-size: 18px; font-weight: bold; color: #333333;">
                      $courseName
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 14px; color: #555555;">
                      📅 <strong>Data:</strong> $courseDate
                    </p>
                    <p style="margin: 0; font-size: 14px; color: #555555;">
                      🕐 <strong>Orario:</strong> $courseTime
                    </p>${_salaRow(sala)}
                  </td>
                </tr>
              </table>

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Non l'hai ancora messa in agenda? Fallo ora:
              </p>

${_calendarButtons(googleUrl: googleUrl, icsUrl: icsUrl)}

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Ricordati di portare abbigliamento comodo e una bottiglietta d'acqua.
              </p>

${_emailCta('Apri Fit House')}

            </td>
          </tr>

${_emailFooter()}

        </table>
      </td>
    </tr>
  </table>
</body>
</html>''';
}

String waitlistSpotAvailableSubject(String courseName) {
  return 'Posto disponibile nel corso "$courseName"!';
}

String waitlistSpotAvailableBody({
  required String courseName,
  required String courseDate,
  required String courseTime,
  required int spotsAvailable,
}) {
  final spotsText = spotsAvailable == 1
      ? '1 posto disponibile'
      : '$spotsAvailable posti disponibili';

  return '''
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
</head>
<body style="margin: 0; padding: 0; background-color: #f4f4f4; font-family: Arial, sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f4f4f4; padding: 40px 0;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden;">

${_emailHeader('Posto disponibile!')}

          <!-- Body -->
          <tr>
            <td style="padding: 30px;">
              <p style="color: #333333; font-size: 16px; line-height: 1.6; margin-top: 0;">
                Ciao,
              </p>
              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Si è liberato un posto nel corso a cui eri in lista d'attesa!
              </p>

              <!-- Course details card -->
              <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f0f2ff; border-radius: 8px; margin: 20px 0;">
                <tr>
                  <td style="padding: 20px;">
                    <p style="margin: 0 0 8px 0; font-size: 18px; font-weight: bold; color: #333333;">
                      $courseName
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 14px; color: #555555;">
                      📅 <strong>Data:</strong> $courseDate
                    </p>
                    <p style="margin: 0 0 4px 0; font-size: 14px; color: #555555;">
                      🕐 <strong>Orario:</strong> $courseTime
                    </p>
                    <p style="margin: 0; font-size: 14px; color: #FF9800; font-weight: bold;">
                      $spotsText
                    </p>
                  </td>
                </tr>
              </table>

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Il posto rimane disponibile per un tempo limitato: apri l'app per iscriverti.
              </p>

${_emailCta('Apri Fit House')}

            </td>
          </tr>

${_emailFooter()}

        </table>
      </td>
    </tr>
  </table>
</body>
</html>''';
}
