import 'package:fitrope_app/utils/course_accordion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CourseAccordion', () {
    test('parte con tutte le righe chiuse', () {
      final a = CourseAccordion();
      expect(a.expandedUid, isNull);
      expect(a.isExpanded('c1'), isFalse);
    });

    test('aprire una riga la segna come aperta', () {
      final a = CourseAccordion()..toggle('c1');
      expect(a.expandedUid, 'c1');
      expect(a.isExpanded('c1'), isTrue);
    });

    test('ritoccare la stessa riga la chiude', () {
      final a = CourseAccordion()
        ..toggle('c1')
        ..toggle('c1');
      expect(a.expandedUid, isNull);
    });

    test('aprire una seconda riga chiude la prima', () {
      // È l'invariante dell'accordion: limita il salto verticale e tiene la
      // giornata scansionabile, che è il senso di partire dall'agenda.
      final a = CourseAccordion()
        ..toggle('c1')
        ..toggle('c2');
      expect(a.expandedUid, 'c2');
      expect(a.isExpanded('c1'), isFalse);
    });

    test('collapse() chiude qualunque riga aperta', () {
      final a = CourseAccordion()..toggle('c1');
      a.collapse();
      expect(a.expandedUid, isNull);
    });

    test('collapse() su tutte chiuse non fa nulla', () {
      final a = CourseAccordion();
      a.collapse();
      expect(a.expandedUid, isNull);
    });

    test('toggle riporta se lo stato è cambiato, per evitare setState inutili',
        () {
      final a = CourseAccordion();
      expect(a.toggle('c1'), isTrue);
      expect(a.toggle('c1'), isTrue);
      expect(a.collapse(), isFalse,
          reason: 'era già chiusa: niente da ridisegnare');
    });

    test('collapse() riporta true solo se c\'era davvero una riga aperta', () {
      final a = CourseAccordion()..toggle('c1');
      expect(a.collapse(), isTrue);
      expect(a.collapse(), isFalse);
    });
  });
}
