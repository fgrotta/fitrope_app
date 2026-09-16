import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lint statico sui conditional import/export di `lib/`.
///
/// `if (dart.library.html)` è `false` sotto `dart2wasm`: una direttiva scritta
/// così sceglie il ramo non-web proprio nella build di produzione
/// (`flutter build web --wasm --release`), e il bug è invisibile in
/// `flutter run -d chrome`, che compila in dart2js. È già successo con
/// `lib/services/onesignal_service.dart`, dove ha spento push e alias email su
/// tutto il web.
///
/// L'unica condizione ammessa è `dart.library.js_interop`, vera sia in dart2js
/// sia in dart2wasm.
void main() {
  test('i conditional import/export di lib/ usano solo dart.library.js_interop',
      () {
    final directive = RegExp(
      r'^\s*(?:import|export)\b[\s\S]*?;',
      multiLine: true,
    );
    final condition = RegExp(r'if\s*\(\s*dart\.library\.(\w+)\s*\)');

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in directive.allMatches(source)) {
        for (final found in condition.allMatches(match.group(0)!)) {
          final library = found.group(1);
          if (library != 'js_interop') {
            offenders.add('${entity.path}: dart.library.$library');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Usa `if (dart.library.js_interop)`: sotto --wasm '
          '`dart.library.html` è false e verrebbe scelto il ramo non-web.\n'
          '${offenders.join('\n')}',
    );
  });
}
