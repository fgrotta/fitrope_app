import 'package:cloud_firestore/cloud_firestore.dart';

/// Famiglia di abbonamento: determina a quali tipologie di corso dà accesso.
enum SubscriptionFamily { OPEN, HYROX, PT }

/// Modalità di addebito di un abbonamento.
/// - FREQUENCY: limite di ingressi a settimana (eventualmente illimitato).
/// - ENTRIES: numero fisso di ingressi che si consumano.
enum BillingMode { FREQUENCY, ENTRIES }

/// Abbonamento dell'utente. In v1 è mantenuto come snapshot denormalizzato in
/// `FitropeUser.activeSubscriptions` (scritto dalle Cloud Functions a partire da
/// PR3); la fonte di verità sarà la collezione `subscriptions`.
class UserSubscription {
  /// Id del documento sorgente nella collezione `subscriptions` (PR3+); null per
  /// snapshot senza riferimento.
  final String? id;
  final String planKey;
  final SubscriptionFamily family;
  final BillingMode billingMode;

  /// Tag dei corsi coperti (accesso). 1:1 con la famiglia (D2).
  final Set<String> courseTypeTags;

  /// Ingressi a settimana per FREQUENCY: 2, 3, oppure null = illimitato.
  final int? weeklyFrequency;

  /// Ingressi residui per ENTRIES.
  final int? remainingEntries;

  final Timestamp startDate;
  final Timestamp endDate;

  const UserSubscription({
    this.id,
    required this.planKey,
    required this.family,
    required this.billingMode,
    required this.courseTypeTags,
    this.weeklyFrequency,
    this.remainingEntries,
    required this.startDate,
    required this.endDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'planKey': planKey,
      'family': family.name,
      'billingMode': billingMode.name,
      'courseTypeTags': courseTypeTags.toList(),
      'weeklyFrequency': weeklyFrequency,
      'remainingEntries': remainingEntries,
      'startDate': startDate,
      'endDate': endDate,
    };
  }

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    return UserSubscription(
      id: json['id'] as String?,
      planKey: json['planKey'] as String,
      family:
          SubscriptionFamily.values.firstWhere((e) => e.name == json['family']),
      billingMode:
          BillingMode.values.firstWhere((e) => e.name == json['billingMode']),
      courseTypeTags: (json['courseTypeTags'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toSet() ??
          {},
      weeklyFrequency: (json['weeklyFrequency'] as num?)?.toInt(),
      remainingEntries: (json['remainingEntries'] as num?)?.toInt(),
      startDate: json['startDate'] as Timestamp,
      endDate: json['endDate'] as Timestamp,
    );
  }
}
