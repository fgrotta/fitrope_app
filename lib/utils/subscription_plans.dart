import 'package:fitrope_app/types/userSubscription.dart';
import 'package:fitrope_app/utils/course_tags.dart';

/// Piano di abbonamento acquistabile (catalogo in codice per la v1).
/// Decompone famiglia × modalità × variante (frequenza/ingressi) × durata.
class SubscriptionPlan {
  final String key;
  final String displayName;
  final SubscriptionFamily family;
  final BillingMode billingMode;

  /// FREQUENCY: 2, 3, oppure null = illimitato.
  final int? weeklyFrequency;

  /// ENTRIES: numero di ingressi del pacchetto.
  final int? entries;

  /// Durata/validità in mesi: 1, 3, 6, 12.
  final int durationMonths;

  /// Tipologie di corso sbloccate (tag).
  final Set<String> grantedCourseTypeTags;

  const SubscriptionPlan({
    required this.key,
    required this.displayName,
    required this.family,
    required this.billingMode,
    this.weeklyFrequency,
    this.entries,
    required this.durationMonths,
    required this.grantedCourseTypeTags,
  });
}

/// Catalogo dei piani. Open: {2x, 3x, illimitato} × {1,3,6,12} = 12;
/// Hyrox e PT: 10 ingressi × {1,3,6,12} = 4 ciascuno (D3).
class SubscriptionPlans {
  static const List<int> durations = [1, 3, 6, 12];
  static const int entriesPerPackage = 10;

  static String _durLabel(int m) => m == 1 ? '1 mese' : '$m mesi';

  static List<SubscriptionPlan> get all => [...open, ...hyrox, ...pt];

  static List<SubscriptionPlan> get open => [
        for (final d in durations) ...[
          SubscriptionPlan(
            key: 'open_2x_${d}m',
            displayName: 'Open 2 volte/sett · ${_durLabel(d)}',
            family: SubscriptionFamily.OPEN,
            billingMode: BillingMode.FREQUENCY,
            weeklyFrequency: 2,
            durationMonths: d,
            grantedCourseTypeTags: const {CourseTags.OPEN},
          ),
          SubscriptionPlan(
            key: 'open_3x_${d}m',
            displayName: 'Open 3 volte/sett · ${_durLabel(d)}',
            family: SubscriptionFamily.OPEN,
            billingMode: BillingMode.FREQUENCY,
            weeklyFrequency: 3,
            durationMonths: d,
            grantedCourseTypeTags: const {CourseTags.OPEN},
          ),
          SubscriptionPlan(
            key: 'open_unlim_${d}m',
            displayName: 'Open illimitato · ${_durLabel(d)}',
            family: SubscriptionFamily.OPEN,
            billingMode: BillingMode.FREQUENCY,
            weeklyFrequency: null,
            durationMonths: d,
            grantedCourseTypeTags: const {CourseTags.OPEN},
          ),
        ],
      ];

  static List<SubscriptionPlan> get hyrox => [
        for (final d in durations)
          SubscriptionPlan(
            key: 'hyrox_${entriesPerPackage}i_${d}m',
            displayName: 'Hyrox $entriesPerPackage ingressi · ${_durLabel(d)}',
            family: SubscriptionFamily.HYROX,
            billingMode: BillingMode.ENTRIES,
            entries: entriesPerPackage,
            durationMonths: d,
            grantedCourseTypeTags: const {CourseTags.HYROX},
          ),
      ];

  static List<SubscriptionPlan> get pt => [
        for (final d in durations)
          SubscriptionPlan(
            key: 'pt_${entriesPerPackage}i_${d}m',
            displayName: 'PT $entriesPerPackage ingressi · ${_durLabel(d)}',
            family: SubscriptionFamily.PT,
            billingMode: BillingMode.ENTRIES,
            entries: entriesPerPackage,
            durationMonths: d,
            grantedCourseTypeTags: const {CourseTags.PERSONAL_TRAINER},
          ),
      ];

  static SubscriptionPlan? byKey(String key) {
    for (final p in all) {
      if (p.key == key) return p;
    }
    return null;
  }
}
