import 'package:cloud_firestore/cloud_firestore.dart';

/// Chi ha registrato la presenza: il socio stesso (check-in "Sono in sala")
/// oppure lo staff durante l'appello.
enum AttendanceSource {
  self,
  trainer,
  admin;

  static AttendanceSource fromString(String? value) {
    switch (value) {
      case 'trainer':
        return AttendanceSource.trainer;
      case 'admin':
        return AttendanceSource.admin;
      default:
        return AttendanceSource.self;
    }
  }
}

/// Documento `attendance/{courseId}_{userId}`: scritto SOLO dalla callable
/// `setAttendance` (le rules negano ogni write client), letto dal socio per
/// sé e dallo staff per l'appello.
class AttendanceRecord {
  final String courseId;
  final String userId;
  final int courseStartMillis;
  final bool present;
  final AttendanceSource source;
  final String? markedBy;

  /// Primo istante di registrazione (non cambia sugli aggiornamenti).
  final Timestamp? markedAt;
  final Timestamp? updatedAt;

  const AttendanceRecord({
    required this.courseId,
    required this.userId,
    required this.courseStartMillis,
    required this.present,
    required this.source,
    this.markedBy,
    this.markedAt,
    this.updatedAt,
  });

  static String docId(String courseId, String userId) => '${courseId}_$userId';

  /// Registrato dallo staff: il socio non può più modificarlo.
  bool get isStaffRecorded => source != AttendanceSource.self;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      courseId: json['courseId'] as String,
      userId: json['userId'] as String,
      courseStartMillis: (json['courseStartMillis'] as num?)?.toInt() ?? 0,
      present: json['present'] == true,
      source: AttendanceSource.fromString(json['source'] as String?),
      markedBy: json['markedBy'] as String?,
      markedAt: json['markedAt'] as Timestamp?,
      updatedAt: json['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
        'courseId': courseId,
        'userId': userId,
        'courseStartMillis': courseStartMillis,
        'present': present,
        'source': source.name,
        'markedBy': markedBy,
        'markedAt': markedAt,
        'updatedAt': updatedAt,
      };

  AttendanceRecord copyWith({
    bool? present,
    AttendanceSource? source,
    String? markedBy,
    Timestamp? updatedAt,
  }) {
    return AttendanceRecord(
      courseId: courseId,
      userId: userId,
      courseStartMillis: courseStartMillis,
      present: present ?? this.present,
      source: source ?? this.source,
      markedBy: markedBy ?? this.markedBy,
      markedAt: markedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Marcatore server-owned `courses/{id}.attendance`: distingue "appello mai
/// fatto" (null) da "nessuno presente" (presentCount 0).
class CourseAttendanceSummary {
  final Timestamp? lastMarkedAt;
  final String? lastMarkedBy;
  final int presentCount;

  const CourseAttendanceSummary({
    this.lastMarkedAt,
    this.lastMarkedBy,
    this.presentCount = 0,
  });

  factory CourseAttendanceSummary.fromJson(Map<String, dynamic> json) {
    return CourseAttendanceSummary(
      lastMarkedAt: json['lastMarkedAt'] as Timestamp?,
      lastMarkedBy: json['lastMarkedBy'] as String?,
      presentCount: (json['presentCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'lastMarkedAt': lastMarkedAt,
        'lastMarkedBy': lastMarkedBy,
        'presentCount': presentCount,
      };

  CourseAttendanceSummary copyWith({int? presentCount}) {
    return CourseAttendanceSummary(
      lastMarkedAt: lastMarkedAt,
      lastMarkedBy: lastMarkedBy,
      presentCount: presentCount ?? this.presentCount,
    );
  }
}
