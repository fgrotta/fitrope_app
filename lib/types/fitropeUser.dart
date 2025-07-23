import 'package:cloud_firestore/cloud_firestore.dart';

class FitropeUser {
  final String uid;
  final String name;
  final String lastName;
  final List<String> courses;
  final TipologiaIscrizione? tipologiaIscrizione;
  final int? entrateDisponibili;
  final int? entrateSettimanali;
  final Timestamp? fineIscrizione;
  final String role;

  const FitropeUser({
    required this.name, 
    required this.lastName, 
    required this.uid, 
    required this.courses, 
    this.tipologiaIscrizione, 
    this.entrateDisponibili,
    this.entrateSettimanali,
    this.fineIscrizione,
    required this.role,
  });

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'lastName': lastName,
      'courses': courses,
      'tipologiaIscrizione': tipologiaIscrizione?.toString().split('.').last,
      'entrateDisponibili': entrateDisponibili,
      'entrateSettimanali': entrateSettimanali,
      'fineIscrizione': fineIscrizione,
      'role': role,
    };
  }

  factory FitropeUser.fromJson(Map<String, dynamic> json) {
    return FitropeUser(
      uid: json['uid'] as String,
      name: json['name'] as String,
      lastName: json['lastName'] as String,
      courses: (json['courses'] as List<dynamic>)
          .map((courseId) => courseId.toString())
          .toList(),
      tipologiaIscrizione: json['tipologiaIscrizione'] != null 
          ? TipologiaIscrizione.values.where((e) => e.toString().split('.').last == json['tipologiaIscrizione']).firstOrNull
          : null,
      entrateDisponibili: json['entrateDisponibili'] as int?,
      entrateSettimanali: json['entrateSettimanali'] as int?,
      fineIscrizione: json['fineIscrizione'] as Timestamp?,
      role: json['role'] ?? 'User',
    );
  }
}

enum TipologiaIscrizione {
  PACCHETTO_ENTRATE,
  ABBONAMENTO_MENSILE,
  ABBONAMENTO_TRIMESTRALE
}