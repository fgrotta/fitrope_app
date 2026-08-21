import 'dart:math' as math;

import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/course_type_style.dart';
import 'package:fitrope_app/utils/course_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Luminanza relativa WCAG di un colore opaco.
double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrastWithWhite(Color c) {
  final l = _relativeLuminance(c);
  return (1.0 + 0.05) / (l + 0.05);
}

void main() {
  group('CourseTypeStyle', () {
    test('ogni tipologia registrata ha uno stile dedicato', () {
      for (final type in CourseTypes.all) {
        expect(courseTypeStyleForKey(type.key), isNot(unknownCourseTypeStyle),
            reason: 'tipologia senza stile: ${type.key}');
      }
    });

    test('le tipologie hanno colori tutti distinti', () {
      final colors = CourseTypes.all
          .map((t) => courseTypeStyleForKey(t.key).color)
          .toList();
      expect(colors.toSet().length, CourseTypes.all.length);
    });

    test('le tipologie hanno icone tutte distinte', () {
      final icons = CourseTypes.all
          .map((t) => courseTypeStyleForKey(t.key).icon)
          .toList();
      expect(icons.toSet().length, CourseTypes.all.length);
    });

    // Il badge mostra testo bianco sul colore della tipologia: è lo stesso
    // impegno che `capacityColor` già documenta per la pill di capienza.
    test('ogni colore garantisce contrasto AA (>= 4.5:1) con testo bianco', () {
      for (final type in CourseTypes.all) {
        final ratio = _contrastWithWhite(courseTypeStyleForKey(type.key).color);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason:
                '${type.key}: contrasto ${ratio.toStringAsFixed(2)}:1 con bianco');
      }
    });

    test('lo stile di ripiego garantisce anch\'esso il contrasto AA', () {
      expect(_contrastWithWhite(unknownCourseTypeStyle.color),
          greaterThanOrEqualTo(4.5));
    });

    test('una chiave sconosciuta ricade sullo stile neutro', () {
      expect(courseTypeStyleForKey('Sconosciuto'), unknownCourseTypeStyle);
      expect(courseTypeStyleForKey(null), unknownCourseTypeStyle);
    });

    test('courseTypeStyleForTags usa la tipologia principale', () {
      expect(courseTypeStyleForTags([CourseTags.HYROX]),
          courseTypeStyleForKey(CourseTags.HYROX));
      // primo tag riconosciuto, come CourseTypes.primaryForTags
      expect(courseTypeStyleForTags(['Sconosciuto', CourseTags.HEY_MAMMA]),
          courseTypeStyleForKey(CourseTags.HEY_MAMMA));
    });

    test('courseTypeStyleForTags su tag vuoti o ignoti ricade sul neutro', () {
      expect(courseTypeStyleForTags([]), unknownCourseTypeStyle);
      expect(courseTypeStyleForTags(['Boh']), unknownCourseTypeStyle);
    });
  });
}
