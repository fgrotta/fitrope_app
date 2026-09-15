import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/utils/course_tags.dart';

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
  final CourseType courseType; // Tipo autoritativo per i documenti V2
  final String? tag; // Etichetta descrittiva singola, mai usata per eligibility
  final bool
      courseModelV2; // Marker esplicito: courseType e affidabile solo se true
  final String? imageKey; // Chiave immagine stock del corso
  final String? sala; // Sala in cui si svolge il corso
  final bool
      reminderEnabled; // Se true, il promemoria email/push viene programmato
  final bool
      waitlistEnabled; // Se true, gli utenti possono mettersi in lista d'attesa

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
    this.courseType = CourseType.open,
    this.tag,
    this.courseModelV2 = false,
    this.imageKey,
    this.sala,
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
    final tags = _parseStringList(json['tags'], field: 'tags');
    final isV2 = json['courseModelV2'] == true;
    final type = isV2
        ? CourseType.fromString(json['courseType'] as String?)
        : _legacyCourseType(tags);
    final tag = isV2
        ? _parseV2Tag(json['tag'])
        : CourseTags.descriptiveTagFromLegacy(tags);
    if (isV2) _validateV2Mirror(type, tag, tags);

    return Course(
      id: localUid,
      uid: localUid,
      name: json['name'] as String,
      startDate: json['startDate'] as Timestamp,
      endDate: json['endDate'] as Timestamp,
      capacity: json['capacity'] as int,
      subscribed: json['subscribed'] as int,
      trainerId: json['trainerId'] as String?,
      tags: tags,
      waitlist: (json['waitlist'] as List<dynamic>?)
              ?.map((id) => id.toString())
              .toList() ??
          [],
      courseType: type,
      tag: tag,
      courseModelV2: isV2,
      imageKey: json['imageKey'] as String?,
      sala: json['sala'] as String?,
      reminderEnabled: json['reminderEnabled'] as bool? ?? true,
      waitlistEnabled: json['waitlistEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    if (!CourseTags.isSelectable(tag) && tag != null) {
      throw FormatException('tag corso V2 sconosciuto: $tag');
    }
    if (courseType == CourseType.personal_trainer &&
        tag != CourseTags.PERSONAL_TRAINER) {
      throw const FormatException(
        'un corso Personal Trainer deve avere il tag Personal Trainer',
      );
    }
    if (courseType == CourseType.open && tag == CourseTags.PERSONAL_TRAINER) {
      throw const FormatException(
        'un corso Open non puo avere il tag Personal Trainer',
      );
    }
    final mirror = CourseTags.legacyTagsMirror(courseType.typeTag, tag);
    return {
      'id': uid,
      'uid': uid,
      'name': name,
      'startDate': startDate,
      'endDate': endDate,
      'capacity': capacity,
      'subscribed': subscribed,
      'trainerId': trainerId,
      'tags': mirror,
      'waitlist': waitlist,
      'courseType': courseType.firestoreValue,
      'tag': tag,
      'courseModelV2': true,
      'imageKey': imageKey,
      'sala': sala,
      'reminderEnabled': reminderEnabled,
      'waitlistEnabled': waitlistEnabled,
    };
  }

  static const Object _unset = Object();

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
    CourseType? courseType,
    Object? tag = _unset,
    bool? courseModelV2,
    String? imageKey,
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
      courseType: courseType ?? this.courseType,
      tag: identical(tag, _unset) ? this.tag : tag as String?,
      courseModelV2: courseModelV2 ?? this.courseModelV2,
      imageKey: imageKey ?? this.imageKey,
      sala: identical(sala, _unset) ? this.sala : sala as String?,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      waitlistEnabled: waitlistEnabled ?? this.waitlistEnabled,
    );
  }

  /// Tipo effettivo del corso. Nei documenti V1 ignora il vecchio
  /// `courseType`, storicamente non affidabile, e deriva esclusivamente da
  /// `tags`; nei V2 usa il campo validato dal parser.
  CourseType get resolvedCourseType =>
      courseModelV2 ? courseType : _legacyCourseType(tags);

  /// Chiave usata da eligibility e conteggio settimanale. Hey Mamma resta
  /// riconosciuto solo sui documenti V1 per non alterarne il comportamento.
  String get resolvedTypeTag {
    if (courseModelV2) return courseType.typeTag;
    if (tags.contains(CourseTags.HEY_MAMMA)) return CourseTags.HEY_MAMMA;
    return _legacyCourseType(tags).typeTag;
  }

  String? get resolvedTag =>
      courseModelV2 ? tag : CourseTags.descriptiveTagFromLegacy(tags);

  /// Tag destinato alle superfici UI. I valori storici read-only (Hey Mamma)
  /// restano risolvibili dal dominio V1 ma non ricompaiono in badge o report.
  String? get displayTag {
    final value = resolvedTag;
    return CourseTags.selectable.contains(value) ? value : null;
  }

  /// Le rules strette consentono il CRUD client solo sui documenti V2.
  bool get isLegacyReadOnly => !courseModelV2;

  bool get hasLegacyReadOnlyTag =>
      !courseModelV2 && tags.contains(CourseTags.HEY_MAMMA);

  static List<String> _parseStringList(dynamic raw, {required String field}) {
    if (raw == null) return const [];
    if (raw is! List || raw.any((value) => value is! String)) {
      throw FormatException('$field deve essere una lista di stringhe');
    }
    return List<String>.unmodifiable(raw.cast<String>());
  }

  static CourseType _legacyCourseType(List<String> tags) {
    if (tags.contains(CourseTags.PERSONAL_TRAINER) &&
        !tags.contains(CourseTags.OPEN)) {
      return CourseType.personal_trainer;
    }
    return CourseType.open;
  }

  static String? _parseV2Tag(dynamic raw) {
    if (raw == null) return null;
    if (raw is! String || !CourseTags.selectable.contains(raw)) {
      throw FormatException('tag corso V2 sconosciuto: $raw');
    }
    return raw;
  }

  static void _validateV2Mirror(
    CourseType type,
    String? tag,
    List<String> tags,
  ) {
    if (type == CourseType.personal_trainer &&
        tag != CourseTags.PERSONAL_TRAINER) {
      throw const FormatException('shape V2 PT senza tag Personal Trainer');
    }
    if (type == CourseType.open && tag == CourseTags.PERSONAL_TRAINER) {
      throw const FormatException('shape V2 Open con tag Personal Trainer');
    }
    final expected = CourseTags.legacyTagsMirror(type.typeTag, tag);
    if (!_sameOrderedList(tags, expected)) {
      throw FormatException('mirror tags V2 invalido: $tags, atteso $expected');
    }
  }

  static bool _sameOrderedList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
