import 'package:fitrope_app/utils/course_form_validation.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/sale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? validate({
    String name = 'Allenamento',
    String? tag = CourseTags.HYROX,
    String? trainerId = 'trainer-1',
    String? sala = Sale.SALA_1,
    int capacity = 6,
  }) =>
      validateCourseSelections(
        name: name,
        tag: tag,
        trainerId: trainerId,
        sala: sala,
        capacity: capacity,
      );

  test('richiede il nome del corso', () {
    expect(validate(name: ''), 'Il nome del corso è obbligatorio');
    expect(validate(name: '  '), 'Il nome del corso è obbligatorio');
  });

  test('richiede un tag selezionabile', () {
    expect(validate(tag: null), 'Seleziona un tag per il corso');
    expect(
      validate(tag: CourseTags.HEY_MAMMA),
      'Seleziona un tag per il corso',
    );
  });

  test('richiede un trainer', () {
    expect(validate(trainerId: null), 'Seleziona un trainer');
    expect(validate(trainerId: ''), 'Seleziona un trainer');
  });

  test('richiede una sala valida', () {
    expect(validate(sala: null), 'Seleziona una sala');
    expect(validate(sala: 'Sala 3'), 'Seleziona una sala');
  });

  test('richiede una capienza positiva', () {
    expect(
      validate(capacity: 0),
      'Il numero di partecipanti deve essere maggiore di 0',
    );
  });

  test('restituisce il primo errore nell ordine visivo dei campi', () {
    expect(
      validate(name: '', tag: null, trainerId: null, sala: null, capacity: 0),
      'Il nome del corso è obbligatorio',
    );
    expect(
      validate(tag: null, trainerId: null, sala: null, capacity: 0),
      'Seleziona un tag per il corso',
    );
  });

  test('accetta tutti i valori validi', () {
    expect(validate(), isNull);
  });
}
