import 'package:fitrope_app/types/userSubscription.dart';
import 'package:fitrope_app/utils/formatDate.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';

/// Etichette di sola lettura per il modello multi-abbonamento
/// (`UserSubscription` / `SubscriptionFamily`). Sono il pendant del nuovo modello
/// rispetto a `getTipologiaIscrizioneLabel` (legacy `TipologiaIscrizione`): pure,
/// senza dipendenze da Flutter, testabili in isolamento.

/// Soglia (giorni) per considerare un abbonamento "in scadenza". Allineata a
/// `AbbonamentoHelper.GIORNI_SOGLIA_SCADENZA_ABBONAMENTO` (15): lì decide il
/// COLORE della card, qui il TESTO di stato, così colore e wording coincidono.
const int kSubscriptionExpiringSoonDays = 15;

/// Etichetta leggibile della famiglia di abbonamento.
String getSubscriptionFamilyLabel(SubscriptionFamily family) {
  switch (family) {
    case SubscriptionFamily.OPEN:
      return 'Open';
    case SubscriptionFamily.HYROX:
      return 'Hyrox';
    case SubscriptionFamily.PT:
      return 'Personal Trainer';
  }
}

/// Descrittore STABILE della variante (non include lo stato consumabile come i
/// residui): usato nel fallback del titolo per piani fuori catalogo.
String _variantDescriptor(UserSubscription s) {
  if (s.billingMode == BillingMode.ENTRIES) return 'pacchetto ingressi';
  final f = s.weeklyFrequency;
  if (f == null) return 'illimitato';
  return '$f${f == 1 ? ' volta' : ' volte'}/sett';
}

/// Titolo dell'abbonamento: usa il `displayName` del catalogo quando il piano è
/// noto; se il piano non è (più) in catalogo compone famiglia + variante STABILE
/// (senza il conteggio residui, che resta sulla riga allowance della card), così
/// uno snapshot di un piano rinominato/rimosso resta leggibile e non duplica la
/// riga sottostante.
String getSubscriptionTitle(UserSubscription s) {
  final plan = SubscriptionPlans.byKey(s.planKey);
  if (plan != null) return plan.displayName;
  return '${getSubscriptionFamilyLabel(s.family)} · ${_variantDescriptor(s)}';
}

/// Riga "residui/frequenza": ingressi residui per ENTRIES (mai negativi, anche
/// con snapshot stantio o residuo sotto zero), frequenza settimanale (o
/// "illimitato") per FREQUENCY.
String getSubscriptionAllowanceLabel(UserSubscription s) {
  if (s.billingMode == BillingMode.ENTRIES) {
    final n = s.remainingEntries ?? 0;
    return 'Ingressi residui: ${n < 0 ? 0 : n}';
  }
  // FREQUENCY: weeklyFrequency null = illimitato.
  final f = s.weeklyFrequency;
  if (f == null) return 'Accessi illimitati';
  return '$f ${f == 1 ? 'volta' : 'volte'} a settimana';
}

/// Riga scadenza già formattata (data in formato esteso it).
String getSubscriptionExpiryLabel(UserSubscription s) =>
    'Scadenza: ${formatDate(s.endDate.toDate())}';

/// Testo di stato dell'abbonamento rispetto a [now] (default: ora). Variante del
/// legacy `AbbonamentoHelper.getStatoAbbonamento` con wording corretto: "Scade
/// oggi" al posto di "Scade tra 0 giorni" e singolare "1 giorno". Stesso confine
/// di `liveSubscriptions` (vivo se [now] non è dopo `endDate`) e stessa soglia di
/// colore (15 gg) → coerente con il colore della card.
///
/// Per i piani a ingressi (ENTRIES) con residui esauriti ma ancora nel periodo
/// di validità ritorna "Esaurito": così il display non mostra un benigno
/// "Valido" mentre `getCourseState` rifiuta l'iscrizione (SUBSCRIBE_LIMIT).
String getSubscriptionStatusLabel(UserSubscription s, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final end = s.endDate.toDate();
  if (ref.isAfter(end)) return 'Scaduto';
  if (s.billingMode == BillingMode.ENTRIES && (s.remainingEntries ?? 0) <= 0) {
    return 'Esaurito';
  }
  final days = end.difference(ref).inDays;
  if (days <= 0) return 'Scade oggi';
  if (days > kSubscriptionExpiringSoonDays) return 'Valido';
  return days == 1 ? 'Scade tra 1 giorno' : 'Scade tra $days giorni';
}

/// Abbonamenti non scaduti rispetto a [now] (default: ora). Mirror del filtro di
/// selezione del modello in `getCourseState`: una voce è viva se [now] NON è
/// successivo a `endDate` (lo snapshot è ricalcolato solo alle scritture, quindi
/// le voci stantie vanno scartate anche lato display).
List<UserSubscription> liveSubscriptions(
  List<UserSubscription> subs, {
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  return subs.where((s) => !ref.isAfter(s.endDate.toDate())).toList();
}
