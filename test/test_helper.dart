import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

class TestHelper {
  static Future<void> setupFirebaseForTesting() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Setup Firebase for testing
    await Firebase.initializeApp();
  }
}
