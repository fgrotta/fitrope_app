import 'package:cloud_firestore/cloud_firestore.dart';

class FitropeUser {
  final String uid;
  final String email;
  final String name;
  final String lastName;
  final List<String> courses;
  final TipologiaIscrizione? tipologiaIscrizione;
  final int? entrateDisponibili;
  final int? entrateSettimanali;
  final Timestamp? fineIscrizione;
  final String role;
  final bool isActive;
  final bool isAnonymous;
  final DateTime createdAt;
  final Timestamp? certificatoScadenza;
  final String? numeroTelefono;

  const FitropeUser({
    required this.name, 
    required this.lastName, 
    required this.uid, 
    required this.email,
    required this.courses, 
    this.tipologiaIscrizione, 
    this.entrateDisponibili,
    this.entrateSettimanali,
    this.fineIscrizione,
    required this.role,
    this.isActive = true,
    this.isAnonymous = false,
    required this.createdAt,
    this.certificatoScadenza,
    this.numeroTelefono,
  });

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'lastName': lastName,
      'courses': courses,
      'tipologiaIscrizione': tipologiaIscrizione?.toString().split('.').last,
      'entrateDisponibili': entrateDisponibili,
      'entrateSettimanali': entrateSettimanali,
      'fineIscrizione': fineIscrizione,
      'role': role,
      'isActive': isActive,
      'isAnonymous': isAnonymous,
      'createdAt': Timestamp.fromDate(createdAt),
      'certificatoScadenza': certificatoScadenza,
      'numeroTelefono': numeroTelefono,
    };
  }

  factory FitropeUser.fromJson(Map<String, dynamic> json) {
    return FitropeUser(
      uid: json['uid'] as String,
      email: json['email'] as String? ?? '',
      name: json['name'] as String,
      lastName: json['lastName'] as String,
      courses: (json['courses'] as List<dynamic>?)
          ?.map((courseId) => courseId.toString())
          .toList() ?? [],
      tipologiaIscrizione: json['tipologiaIscrizione'] != null 
          ? TipologiaIscrizione.values.where((e) => e.toString().split('.').last == json['tipologiaIscrizione']).firstOrNull
          : null,
      entrateDisponibili: json['entrateDisponibili'] as int?,
      entrateSettimanali: json['entrateSettimanali'] as int?,
      fineIscrizione: json['fineIscrizione'] as Timestamp?,
      role: json['role'] ?? 'User',
      isActive: json['isActive'] as bool? ?? true,
      isAnonymous: json['isAnonymous'] as bool? ?? false,
      createdAt: json['createdAt'] != null 
          ? (json['createdAt'] as Timestamp).toDate() 
          : DateTime.now(),
      certificatoScadenza: json['certificatoScadenza'] as Timestamp?,
      numeroTelefono: json['numeroTelefono'] as String?,
    );
  }
}

enum TipologiaIscrizione {
  PACCHETTO_ENTRATE,
  ABBONAMENTO_MENSILE,
  ABBONAMENTO_TRIMESTRALE,
  ABBONAMENTO_SEMESTRALE,
  ABBONAMENTO_ANNUALE,
  ABBONAMENTO_PROVA // Nuovo abbonamento di prova
}