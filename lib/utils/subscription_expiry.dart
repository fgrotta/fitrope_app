import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/types/user_subscription.dart';
import 'package:fitrope_app/utils/get_tipologia_iscrizione_label.dart';
import 'package:fitrope_app/utils/subscription_labels.dart';

/// Una riga di scadenza: per V2 ce n'e' una per piano, per V1 una sola riga
/// legacy. Evita di comprimere arbitrariamente piu piani in una data "max".
class SubscriptionExpiry {
  final String label;
  final Timestamp? endDate;
  final bool legacy;
  const SubscriptionExpiry(this.label, this.endDate, {this.legacy = false});
}

/// Modello multi-abbonamento se il documento è V2 o lo snapshot contiene voci
/// non scadute; altrimenti campi legacy. Stessa selezione di `getCourseState`
/// (e del server, `evaluateSubscribe`): un documento V1 con uno snapshot vivo
/// è già sul modello nuovo, e leggerne la `fineIscrizione` (spesso null)
/// farebbe sparire i suoi abbonamenti.
bool _usesSubscriptionModel(FitropeUser user, DateTime now) =>
    user.subscriptionModelVersion >= 2 ||
    liveSubscriptions(user.activeSubscriptions, now: now).isNotEmpty;

List<SubscriptionExpiry> subscriptionExpiries(
  FitropeUser user, {
  DateTime? now,
}) {
  if (_usesSubscriptionModel(user, now ?? DateTime.now())) {
    return user.activeSubscriptions
        .map((UserSubscription s) => SubscriptionExpiry(
              getSubscriptionTitle(s),
              s.endDate,
            ))
        .toList()
      ..sort((a, b) => (a.endDate?.millisecondsSinceEpoch ?? 0)
          .compareTo(b.endDate?.millisecondsSinceEpoch ?? 0));
  }
  return [
    SubscriptionExpiry(
      user.tipologiaIscrizione == null
          ? 'Piano legacy'
          : getTipologiaIscrizioneLabel(user.tipologiaIscrizione!),
      user.fineIscrizione,
      legacy: true,
    )
  ];
}

/// Finestra "in scadenza": [end] è dopo [now] e al più 30 giorni dopo
/// (estremo finale compreso). Unica definizione, condivisa dal KPI e dalla
/// sua ripartizione per durata, così i numeri non divergono sui bordi.
bool expiresInNext30Days(DateTime end, DateTime now) =>
    end.isAfter(now) && !end.isAfter(now.add(const Duration(days: 30)));

List<SubscriptionExpiry> subscriptionsExpiringInNext30Days(
  FitropeUser user, {
  DateTime? now,
}) {
  final start = now ?? DateTime.now();
  return subscriptionExpiries(user, now: start).where((expiry) {
    final date = expiry.endDate?.toDate();
    return date != null && expiresInNext30Days(date, start);
  }).toList();
}

int countSubscriptionsExpiringInNext30Days(
  Iterable<FitropeUser> users, {
  DateTime? now,
}) {
  return users.fold<int>(
    0,
    (total, user) =>
        total + subscriptionsExpiringInNext30Days(user, now: now).length,
  );
}

/// Vero se il profilo ha almeno un abbonamento non scaduto rispetto a [now]
/// (default: ora): uno snapshot vivo (stesso confine di `liveSubscriptions`,
/// vivo fino a `endDate` compreso) oppure, per i soli documenti V1 senza
/// snapshot vivo, una `fineIscrizione` non ancora passata.
bool hasLiveSubscription(FitropeUser user, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  if (liveSubscriptions(user.activeSubscriptions, now: ref).isNotEmpty) {
    return true;
  }
  if (user.subscriptionModelVersion >= 2) return false;
  final end = user.fineIscrizione?.toDate();
  return end != null && !ref.isAfter(end);
}

/// Complemento di [hasLiveSubscription]: nessun abbonamento, oppure solo
/// abbonamenti scaduti ancora presenti nello snapshot o nella data legacy.
bool hasNoActiveSubscription(FitropeUser user, {DateTime? now}) =>
    !hasLiveSubscription(user, now: now);

bool hasSubscriptionExpiringInNext30Days(FitropeUser user, {DateTime? now}) {
  return subscriptionsExpiringInNext30Days(user, now: now).isNotEmpty;
}
