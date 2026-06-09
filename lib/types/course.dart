import 'package:cloud_firestore/cloud_firestore.dart';

class Course {
  @Deprecated('Use uid instead')
  final String id;
  final String uid;
  final String name;
  final Timestamp startDate;
  final Timestamp endDate;
  final int capacity;
  final int subscribed;
  final String? trainerId; // ID del trainer assegnato al corso
  final List<String> tags; // Tag per limitare l'accesso al corso
  final List<String> waitlist; // Utenti in lista d'attesa (user IDs)
  final bool
      reminderEnabled; // Se true, il promemoria email/push viene programmato
  final bool
      waitlistEnabled; // Se true, gli utenti possono mettersi in lista d'attesa
  final String?
      sala; // Sala in cui si svolge il corso (lista chiusa, vedi Sale)

  const Course({
    @Deprecated('Use uid instead') required this.id,
    required this.uid,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.capacity,
    required this.subscribed,
    this.trainerId,
    this.tags = const [],
    this.waitlist = const [],
    this.reminderEnabled = true,
    this.waitlistEnabled = true,
    this.sala,
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    var localUid = '';
    if (json['uid'] != null) {
      localUid = json['uid'] as String;
    } else {
      localUid = json['id'] as String;
    }
    return Course(
      id: localUid,
      uid: localUid,
      name: json['name'] as String,
      startDate: json['startDate'] as Timestamp,
      endDate: json['endDate'] as Timestamp,
      capacity: json['capacity'] as int,
      subscribed: json['subscribed'] as int,
      trainerId: json['trainerId'] as String?,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((tag) => tag.toString())
              .toList() ??
          [],
      waitlist: (json['waitlist'] as List<dynamic>?)
              ?.map((id) => id.toString())
              .toList() ??
          [],
      reminderEnabled: json['reminderEnabled'] as bool? ?? true,
      waitlistEnabled: json['waitlistEnabled'] as bool? ?? true,
      sala: json['sala'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': uid,
      'uid': uid,
      'name': name,
      'startDate': startDate,
      'endDate': endDate,
      'capacity': capacity,
      'subscribed': subscribed,
      'trainerId': trainerId,
      'tags': tags,
      'waitlist': waitlist,
      'reminderEnabled': reminderEnabled,
      'waitlistEnabled': waitlistEnabled,
      'sala': sala,
    };
  }

  /// Sentinella per distinguere "parametro non passato" da "passato null"
  /// nei campi nullable di [copyWith] (trainerId, sala).
  static const Object _unset = Object();

  /// Copia il corso sovrascrivendo solo i campi indicati; gli altri sono
  /// preservati. Evita la copia manuale campo-per-campo (fonte di bug se si
  /// dimentica un campo). `id` rispecchia `uid` salvo override esplicito.
  /// Per i campi nullable [trainerId] e [sala]: passare `null` esplicito li
  /// AZZERA, ometterli li preserva.
  Course copyWith({
    String? id,
    String? uid,
    String? name,
    Timestamp? startDate,
    Timestamp? endDate,
    int? capacity,
    int? subscribed,
    Object? trainerId = _unset,
    List<String>? tags,
    List<String>? waitlist,
    bool? reminderEnabled,
    bool? waitlistEnabled,
    Object? sala = _unset,
  }) {
    final newUid = uid ?? this.uid;
    return Course(
      id: id ?? newUid,
      uid: newUid,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      capacity: capacity ?? this.capacity,
      subscribed: subscribed ?? this.subscribed,
      trainerId:
          identical(trainerId, _unset) ? this.trainerId : trainerId as String?,
      tags: tags ?? this.tags,
      waitlist: waitlist ?? this.waitlist,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      waitlistEnabled: waitlistEnabled ?? this.waitlistEnabled,
      sala: identical(sala, _unset) ? this.sala : sala as String?,
    );
  }
}
