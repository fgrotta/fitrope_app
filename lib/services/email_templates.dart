/// URL pubblico del logo usato nelle email.
/// Hostato sul dominio Firebase Hosting (le email OneSignal caricano immagini
/// via HTTP, quindi servono asset pubblici — gli asset Flutter locali non
/// sarebbero accessibili).
const String _logoUrl =
    'https://fit-rope-app-1f575.web.app/assets/assets/new_logo_only.png';

String _emailHeader(String title) {
  return '''
          <!-- Header con logo -->
          <tr>
            <td style="background-color: #6077F6; padding: 24px 30px; text-align: center;">
              <img src="$_logoUrl" alt="Fit House" width="90" height="90"
                   style="display: block; margin: 0 auto 12px auto; border: 0;" />
              <h1 style="color: #ffffff; margin: 0; font-size: 22px; font-weight: 600;">
                $title
              </h1>
            </td>
          </tr>''';
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

String trialReminderSubject(String courseName) {
  return 'Promemoria: la tua lezione di prova "$courseName" è domani!';
}

String trialReminderBody({
  required String courseName,
  required String courseDate,
  required String courseTime,
}) {
  return '''
<html>
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
                    </p>
                  </td>
                </tr>
              </table>

              <p style="color: #333333; font-size: 16px; line-height: 1.6;">
                Ricordati di portare abbigliamento comodo e una bottiglietta d'acqua.
              </p>

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
                Iscriviti subito prima che il posto venga occupato!
              </p>

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
