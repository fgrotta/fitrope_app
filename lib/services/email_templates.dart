// TODO: Sostituire con l'URL reale dell'app/sito
const String appUrl = 'https://your-app-url.com';

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
          
          <!-- Header -->
          <tr>
            <td style="background-color: #6077F6; padding: 30px; text-align: center;">
              <h1 style="color: #ffffff; margin: 0; font-size: 24px;">Posto disponibile!</h1>
            </td>
          </tr>
          
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
              
              <!-- CTA Button -->
              <table width="100%" cellpadding="0" cellspacing="0" style="margin: 30px 0;">
                <tr>
                  <td align="center">
                    <a href="$appUrl" 
                       style="display: inline-block; background-color: #6077F6; color: #ffffff; text-decoration: none; padding: 14px 40px; border-radius: 8px; font-size: 16px; font-weight: bold;">
                      Apri l'app e iscriviti
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Footer -->
          <tr>
            <td style="background-color: #f9f9f9; padding: 20px; text-align: center; border-top: 1px solid #eeeeee;">
              <p style="color: #999999; font-size: 12px; margin: 0;">
                — Il team Fit House
              </p>
            </td>
          </tr>
          
        </table>
      </td>
    </tr>
  </table>
</body>
</html>''';
}
