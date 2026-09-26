import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:fitrope_app/utils/intl_it.dart';

/// `main.dart` inizializza solo i dati italiani (niente
/// `date_symbol_data_local`): i `DateFormat` con `it_IT` devono restare in
/// italiano, con la locale completa che ricade su `it`.
void main() {
  setUpAll(initializeItalianDateFormatting);

  test("DateFormat('EEEE d MMMM', 'it_IT') produce nomi italiani", () {
    expect(DateFormat('EEEE d MMMM', 'it_IT').format(DateTime(2026, 9, 28)),
        'lunedì 28 settembre');
  });

  test('gli skeleton usano i pattern italiani', () {
    expect(DateFormat.yMd('it_IT').format(DateTime(2026, 1, 5)), '05/01/2026');
    expect(DateFormat.MMMEd('it').format(DateTime(2026, 1, 5)), 'lun 5 gen');
  });
}
