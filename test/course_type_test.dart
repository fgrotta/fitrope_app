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

    test('getDefaultImage usa il default esplicito se presente', () {
      // Open ha un default esplicito (open_stock), indipendente dall'ordine.
      expect(
        CourseImages.getDefaultImage(CourseType.open),
        'assets/course_images/open_stock.webp',
      );
      expect(
        CourseImages.getDefaultImage(CourseType.open),
        CourseImages.defaultByType[CourseType.open],
      );
    });

    test('getDefaultImage ricade sulla prima immagine se non c\'è default esplicito', () {
      // Personal Trainer non ha un default esplicito: usa la prima del catalogo.
      expect(CourseImages.defaultByType.containsKey(CourseType.personal_trainer),
          isFalse);
      expect(
        CourseImages.getDefaultImage(CourseType.personal_trainer),
        CourseImages.forType(CourseType.personal_trainer).first,
      );
    });

    test('getCourseImage usa imageKey quando è una chiave valida del catalogo', () {
      final course = buildCourse(
        courseType: CourseType.open,
        imageKey: 'assets/course_images/pt_2.webp',
      );
      expect(CourseImages.getCourseImage(course), 'assets/course_images/pt_2.webp');
    });

    test('getCourseImage ignora un imageKey non più nel catalogo e usa il default', () {
      // imageKey "stale" (asset rinominato/rimosso): deve ricadere sul default del tipo.
      final stale = buildCourse(
        courseType: CourseType.personal_trainer,
        imageKey: 'assets/course_images/pt_2.png', // estensione vecchia, non più nel catalogo
      );
      expect(
        CourseImages.getCourseImage(stale),
        CourseImages.getDefaultImage(CourseType.personal_trainer),
      );
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

    test('l\'immagine di default esiste su disco', () {
      expect(File(CourseImages.defaultImage).existsSync(), isTrue,
          reason: 'asset di default mancante: ${CourseImages.defaultImage}');
    });
  });

  group('Course serializzazione campi categorizzazione', () {
    test('toJson include courseType e imageKey', () {
      final json = buildCourse(
        courseType: CourseType.personal_trainer,
        imageKey: 'assets/course_images/pt_1.webp',
      ).toJson();
      expect(json['courseType'], 'personal_trainer');
      expect(json['imageKey'], 'assets/course_images/pt_1.webp');
    });

    test('fromJson legge courseType e imageKey', () {
      final json = buildCourse(
        courseType: CourseType.personal_trainer,
        imageKey: 'assets/course_images/pt_3.webp',
      ).toJson();
      final parsed = Course.fromJson(json);
      expect(parsed.courseType, CourseType.personal_trainer);
      expect(parsed.imageKey, 'assets/course_images/pt_3.webp');
    });

    test('fromJson usa open come default quando courseType manca', () {
      final json = buildCourse().toJson()..remove('courseType');
      final parsed = Course.fromJson(json);
      expect(parsed.courseType, CourseType.open);
    });

    test('round-trip preserva imageKey null', () {
      final json = buildCourse(imageKey: null).toJson();
      expect(json['imageKey'], isNull);
      expect(Course.fromJson(json).imageKey, isNull);
    });

    test('round-trip toJson/fromJson preserva la categorizzazione', () {
      final original = buildCourse(
        courseType: CourseType.personal_trainer,
        imageKey: 'assets/course_images/pt_2.webp',
      );
      final parsed = Course.fromJson(original.toJson());
      expect(parsed.courseType, original.courseType);
      expect(parsed.imageKey, original.imageKey);
    });
  });
}
