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
  final bool reminderEnabled; // Se true, il promemoria email/push viene programmato
  final bool waitlistEnabled; // Se true, gli utenti possono mettersi in lista d'attesa

  const Course({
    @Deprecated('Use uid instead')
    required this.id,
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
      tags: (json['tags'] as List<dynamic>?)?.map((tag) => tag.toString()).toList() ?? [],
      waitlist: (json['waitlist'] as List<dynamic>?)?.map((id) => id.toString()).toList() ?? [],
      reminderEnabled: json['reminderEnabled'] as bool? ?? true,
      waitlistEnabled: json['waitlistEnabled'] as bool? ?? true,
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
    };
  }
}
