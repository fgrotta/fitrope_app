import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/utils/course_images.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Test per la categorizzazione dei corsi: enum CourseType, mappatura immagini
/// CourseImages e serializzazione dei campi courseType/imageKey nel modello Course.
void main() {
  final now = DateTime.now();

  Course buildCourse({CourseType courseType = CourseType.open, String? imageKey}) {
    return Course(
      id: 'c1',
      uid: 'c1',
      name: 'Corso',
      startDate: Timestamp.fromDate(now),
      endDate: Timestamp.fromDate(now.add(const Duration(hours: 1))),
      capacity: 10,
      subscribed: 0,
      courseType: courseType,
      imageKey: imageKey,
    );
  }

  group('CourseType enum', () {
    test('label è in italiano per ogni valore', () {
      expect(CourseType.open.label, 'Open');
      expect(CourseType.personal_trainer.label, 'Personal Trainer');
    });

    test('firestoreValue corrisponde al name', () {
      expect(CourseType.open.firestoreValue, 'open');
      expect(CourseType.personal_trainer.firestoreValue, 'personal_trainer');
    });

    test('fromString fa il round-trip dei valori validi', () {
      expect(CourseType.fromString('open'), CourseType.open);
      expect(CourseType.fromString('personal_trainer'), CourseType.personal_trainer);
    });

    test('fromString ritorna open come fallback per null o valori sconosciuti', () {
      expect(CourseType.fromString(null), CourseType.open);
      expect(CourseType.fromString(''), CourseType.open);
      expect(CourseType.fromString('inesistente'), CourseType.open);
    });
  });

  group('CourseImages', () {
    test('ogni tipologia ha almeno un\'immagine', () {
      for (final type in CourseType.values) {
        expect(CourseImages.forType(type), isNotEmpty,
            reason: 'manca il catalogo immagini per $type');
      }
    });

    test('all contiene tutte le immagini di tutti i tipi senza perderne', () {
      final expected = CourseType.values
          .expand((t) => CourseImages.forType(t))
          .length;
      expect(CourseImages.all.length, expected);
    });

    test('getDefaultImage ritorna la prima immagine del tipo', () {
      expect(
        CourseImages.getDefaultImage(CourseType.open),
        CourseImages.forType(CourseType.open).first,
      );
      expect(
        CourseImages.getDefaultImage(CourseType.personal_trainer),
        CourseImages.forType(CourseType.personal_trainer).first,
      );
    });

    test('getCourseImage usa imageKey quando presente', () {
      final course = buildCourse(
        courseType: CourseType.open,
        imageKey: 'assets/course_images/pt_2.png',
      );
      expect(CourseImages.getCourseImage(course), 'assets/course_images/pt_2.png');
    });

    test('getCourseImage fa fallback sul default del tipo se imageKey è nullo o vuoto', () {
      final senzaKey = buildCourse(courseType: CourseType.personal_trainer);
      expect(
        CourseImages.getCourseImage(senzaKey),
        CourseImages.getDefaultImage(CourseType.personal_trainer),
      );

      final keyVuota = buildCourse(courseType: CourseType.open, imageKey: '');
      expect(
        CourseImages.getCourseImage(keyVuota),
        CourseImages.getDefaultImage(CourseType.open),
      );
    });

    test('tutti i path del catalogo puntano a file esistenti', () {
      // Gli asset placeholder devono esistere su disco e in pubspec.yaml.
      for (final path in CourseImages.all) {
        expect(File(path).existsSync(), isTrue, reason: 'asset mancante: $path');
      }
    });
  });

  group('Course serializzazione campi categorizzazione', () {
    test('toJson include courseType e imageKey', () {
      final json = buildCourse(
        courseType: CourseType.personal_trainer,
        imageKey: 'assets/course_images/pt_1.png',
      ).toJson();
      expect(json['courseType'], 'personal_trainer');
      expect(json['imageKey'], 'assets/course_images/pt_1.png');
    });

    test('fromJson legge courseType e imageKey', () {
      final json = buildCourse(
        courseType: CourseType.personal_trainer,
        imageKey: 'assets/course_images/pt_3.png',
      ).toJson();
      final parsed = Course.fromJson(json);
      expect(parsed.courseType, CourseType.personal_trainer);
      expect(parsed.imageKey, 'assets/course_images/pt_3.png');
    });

    test('fromJson usa open come default quando courseType manca', () {
      final json = buildCourse().toJson()..remove('courseType');
      final parsed = Course.fromJson(json);
      expect(parsed.courseType, CourseType.open);
    });

    test('round-trip toJson/fromJson preserva la categorizzazione', () {
      final original = buildCourse(
        courseType: CourseType.personal_trainer,
        imageKey: 'assets/course_images/pt_2.png',
      );
      final parsed = Course.fromJson(original.toJson());
      expect(parsed.courseType, original.courseType);
      expect(parsed.imageKey, original.imageKey);
    });
  });
}
