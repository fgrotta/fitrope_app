import 'package:fitrope_app/services/notification_service.dart';
import 'package:fitrope_app/state/simulation_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/simulation_users.dart';

void main() {
  tearDown(SimulationSession.stop);

  test('la simulazione blocca tutti gli invii debug prima di Firebase', () {
    SimulationSession.start(
      admin: simUser(uid: 'admin', role: 'Admin'),
      target: simUser(uid: 'user', role: 'User'),
    );
    final start = DateTime(2026, 10, 20, 10);
    final end = start.add(const Duration(hours: 1));
    expect(
      () => sendTestWaitlistEmail(
        userId: 'user',
        courseName: 'Pilates',
        courseDate: '20 ottobre',
        courseTime: '10:00',
        spotsAvailable: 1,
      ),
      throwsA(isA<SimulationBlockedException>()),
    );
    expect(
      () => sendTestTrialReminderEmail(
        userId: 'user',
        courseName: 'Pilates',
        courseDate: '20 ottobre',
        courseTime: '10:00',
        courseId: 'c1',
        eventStart: start,
        eventEnd: end,
      ),
      throwsA(isA<SimulationBlockedException>()),
    );
    expect(
      () => sendTestTrialConfirmationEmail(
        userId: 'user',
        courseName: 'Pilates',
        courseDate: '20 ottobre',
        courseTime: '10:00',
        courseId: 'c1',
        eventStart: start,
        eventEnd: end,
      ),
      throwsA(isA<SimulationBlockedException>()),
    );
  });
}
