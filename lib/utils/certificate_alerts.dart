import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/certificato_helper.dart';
import 'package:fitrope_app/utils/subscription_labels.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';

/// Stato del certificato medico che richiede un intervento dell'admin.
enum CertificatoAlert { mancante, scaduto, inScadenza }

/// Stato del certificato di [u] rispetto a [now] (default: ora), oppure `null`
/// se il certificato è valido oltre [sogliaGiorni] (default
/// [CertificatoHelper.GIORNI_SOGLIA_SCADENZA]). Lo scaduto si decide
/// sull'istante, non sui giorni interi: un certificato scaduto da poche ore è
/// già scaduto.
CertificatoAlert? certificatoAlertOf(
  FitropeUser u, {
  DateTime? now,
  int sogliaGiorni = CertificatoHelper.GIORNI_SOGLIA_SCADENZA,
}) {
  final ref = now ?? DateTime.now();
  final scadenza = u.certificatoScadenza?.toDate();
  if (scadenza == null) return CertificatoAlert.mancante;
  if (scadenza.isBefore(ref)) return CertificatoAlert.scaduto;
  final soglia = ref.add(Duration(days: sogliaGiorni));
  if (!scadenza.isAfter(soglia)) return CertificatoAlert.inScadenza;
  return null;
}

/// Finestra dell'"in scadenza" nel filtro della lista utenti: più larga della
/// soglia di dashboard e badge, per trovare chi rinnovare con anticipo.
const int giorniSogliaFiltroCertificato = 30;

/// Filtro sul certificato medico nella lista utenti dell'admin.
enum CertificatoListFilter {
  tutti,
  scadutoOInScadenza,
  scaduto,
  inScadenza,
  mancante,
}

/// Vero se [u] passa il filtro [f]. A differenza di
/// [usersNeedingCertificateAttention] non richiede un abbonamento vivo: è una
/// ricerca, e si combina con gli altri filtri della lista.
bool matchesCertificatoFilter(
  FitropeUser u,
  CertificatoListFilter f, {
  DateTime? now,
}) {
  final alert = certificatoAlertOf(
    u,
    now: now,
    sogliaGiorni: giorniSogliaFiltroCertificato,
  );
  return switch (f) {
    CertificatoListFilter.tutti => true,
    CertificatoListFilter.scadutoOInScadenza =>
      alert == CertificatoAlert.scaduto || alert == CertificatoAlert.inScadenza,
    CertificatoListFilter.scaduto => alert == CertificatoAlert.scaduto,
    CertificatoListFilter.inScadenza => alert == CertificatoAlert.inScadenza,
    CertificatoListFilter.mancante => alert == CertificatoAlert.mancante,
  };
}

/// Giorni di calendario da [now] alla scadenza del certificato: 0 se scade
/// oggi, negativo se è già passata. `null` senza certificato.
int? giorniAllaScadenzaCertificato(FitropeUser u, {DateTime? now}) {
  final scadenza = u.certificatoScadenza?.toDate();
  if (scadenza == null) return null;
  final ref = now ?? DateTime.now();
  final oggi = DateTime(ref.year, ref.month, ref.day);
  final giorno = DateTime(scadenza.year, scadenza.month, scadenza.day);
  return giorno.difference(oggi).inDays;
}

/// Vero se [u] ha almeno un abbonamento vivo che non sia la Prova. Stessa
/// scelta di modello di `hasLiveSubscription`: gli snapshot V2 vivi, se ci
/// sono, decidono da soli; un documento V2 senza snapshot vivi non ha
/// abbonamenti; un documento legacy V1 conta se `fineIscrizione` non è passata
/// e la tipologia non è la Prova. Conta solo la data: un pacchetto con 0
/// ingressi ma non scaduto resta vivo.
bool hasNonTrialLiveSubscription(FitropeUser u, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final live = liveSubscriptions(u.activeSubscriptions, now: ref);
  if (live.isNotEmpty) {
    return live.any((s) => s.planKey != SubscriptionPlans.trial.key);
  }
  if (u.subscriptionModelVersion >= 2) return false;
  final end = u.fineIscrizione?.toDate();
  final tipologia = u.tipologiaIscrizione;
  return end != null &&
      !ref.isAfter(end) &&
      tipologia != null &&
      tipologia != TipologiaIscrizione.ABBONAMENTO_PROVA;
}

/// Soci attivi con un abbonamento vivo non di prova e un certificato
/// mancante, scaduto o in scadenza. Ordine: i mancanti per nome, poi gli
/// scaduti dal più vecchio, poi gli in scadenza dal più vicino. Admin e Trainer
/// escono da soli perché non hanno abbonamenti; se li hanno, valgono come soci.
List<FitropeUser> usersNeedingCertificateAttention(
  Iterable<FitropeUser> users, {
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final flagged = <(FitropeUser, CertificatoAlert)>[];
  for (final u in users) {
    if (!u.isActive || !hasNonTrialLiveSubscription(u, now: ref)) continue;
    final alert = certificatoAlertOf(u, now: ref);
    if (alert != null) flagged.add((u, alert));
  }

  String nome(FitropeUser u) => '${u.name} ${u.lastName}'.toLowerCase();

  flagged.sort((a, b) {
    final (userA, alertA) = a;
    final (userB, alertB) = b;
    final byAlert = alertA.index.compareTo(alertB.index);
    if (byAlert != 0) return byAlert;
    if (alertA == CertificatoAlert.mancante) {
      return nome(userA).compareTo(nome(userB));
    }
    return userA.certificatoScadenza!.compareTo(userB.certificatoScadenza!);
  });
  return [for (final (u, _) in flagged) u];
}
