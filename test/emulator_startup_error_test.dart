import 'package:fitrope_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('spiega come recuperare quando la pulizia Auth è bloccata',
      (tester) async {
    await tester.pumpWidget(
      const EmulatorStartupErrorApp(details: 'IndexedDB bloccato'),
    );

    expect(find.text('Avvio emulatore bloccato'), findsOneWidget);
    expect(find.textContaining('Chiudi le altre schede'), findsOneWidget);
    expect(find.text('IndexedDB bloccato'), findsOneWidget);
  });
}
