import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/utils/italian_time.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';

/// Date di un abbonamento scelte dall'Admin a giorni interi, in orario di
/// Roma: l'inizio vale dalle 00:00 del giorno scelto, la fine fino alle
/// 23:59:59.999, indipendentemente dal fuso del dispositivo.

/// Giorno di fine predefinito: inizio + durata del piano (mesi di calendario
/// con clamp a fine mese, come `addMonths` server-side; giorni per la Prova).
DateTime defaultEndDate(SubscriptionPlan plan, DateTime start) {
  final day = DateTime(start.year, start.month, start.day);
  final days = plan.durationDays;
  if (days != null) return DateTime(day.year, day.month, day.day + days);
  final targetMonth = DateTime(day.year, day.month + plan.durationMonths!);
  final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
  return DateTime(
    targetMonth.year,
    targetMonth.month,
    day.day < lastDay ? day.day : lastDay,
  );
}

/// Istante di inizio: 00:00 di Roma del giorno [day].
Timestamp subscriptionStartTimestamp(DateTime day) =>
    italianTimestamp(DateTime(day.year, day.month, day.day));

/// Istante di fine: 23:59:59.999 di Roma del giorno [day].
Timestamp subscriptionEndTimestamp(DateTime day) {
  final lastSecond =
      italianTimestamp(DateTime(day.year, day.month, day.day, 23, 59, 59));
  return Timestamp.fromMillisecondsSinceEpoch(
    lastSecond.millisecondsSinceEpoch + 999,
  );
}

/// Giorno di Roma (solo data) di un istante salvato.
DateTime romeDay(Timestamp ts) {
  final rome = toItalianTime(ts.toDate());
  return DateTime(rome.year, rome.month, rome.day);
}
