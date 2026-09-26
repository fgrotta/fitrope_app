import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/api/subscriptions/signup_trial.dart';

/// Il login chiama la callable `grantSignupTrial` (e rilegge il profilo) solo
/// se il documento appena letto ha il marker della self-registration: per
/// tutti gli altri il server risponderebbe `NOT_PENDING` dopo un round-trip.
void main() {
  test('marker presente → serve la callable', () {
    expect(needsSignupTrialGrant({'signupTrialRequested': true}), isTrue);
  });

  test('marker assente, falso o di tipo sbagliato → nessuna callable', () {
    expect(needsSignupTrialGrant({}), isFalse);
    expect(needsSignupTrialGrant({'signupTrialRequested': false}), isFalse);
    expect(needsSignupTrialGrant({'signupTrialRequested': 'true'}), isFalse);
  });
}
