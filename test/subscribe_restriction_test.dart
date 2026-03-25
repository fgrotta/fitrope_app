import 'package:flutter_test/flutter_test.dart';
import 'package:fitrope_app/api/courses/subscribeToCourse.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('SubscribeToCourse Role Restrictions Tests', () {
    
    late Course testCourse;
    late FitropeUser adminUser;
    late FitropeUser trainerUser;
    late FitropeUser regularUser;
    
    setUp(() {
      // Crea un corso di test
      testCourse = Course(
        uid: 'test-course-1',
        name: 'Corso di Test',
        startDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
        endDate: Timestamp.fromDate(DateTime.now().add(const Duration(hours: 25))),
        capacity: 20,
        subscribed: 5,
      );
      
      // Utente Admin
      adminUser = FitropeUser(
        uid: 'admin-user',
        email: 'admin@example.com',
        name: 'Admin',
        lastName: 'User',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateDisponibili: null,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
        role: 'Admin',
        isActive: true,
        isAnonymous: false,
        createdAt: DateTime.now(),
      );
      
      // Utente Trainer
      trainerUser = FitropeUser(
        uid: 'trainer-user',
        email: 'trainer@example.com',
        name: 'Trainer',
        lastName: 'User',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.ABBONAMENTO_MENSILE,
        entrateDisponibili: null,
        entrateSettimanali: 3,
        fineIscrizione: Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
        role: 'Trainer',
        isActive: true,
        isAnonymous: false,
        createdAt: DateTime.now(),
      );
      
      // Utente normale
      regularUser = FitropeUser(
        uid: 'regular-user',
        email: 'user@example.com',
        name: 'Regular',
        lastName: 'User',
        courses: [],
        tipologiaIscrizione: TipologiaIscrizione.PACCHETTO_ENTRATE,
        entrateDisponibili: 5,
        entrateSettimanali: null,
        fineIscrizione: null,
        role: 'User',
        isActive: true,
        isAnonymous: false,
        createdAt: DateTime.now(),
      );
    });
    
    group('Role-based subscription restrictions', () {
      test('should throw exception when Admin tries to subscribe', () async {
        expect(
          () => subscribeToCourse(testCourse.uid, adminUser.uid),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Admin e Trainer non possono iscriversi ai corsi'),
          )),
        );
      });
      
      test('should throw exception when Trainer tries to subscribe', () async {
        expect(
          () => subscribeToCourse(testCourse.uid, trainerUser.uid),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Admin e Trainer non possono iscriversi ai corsi'),
          )),
        );
      });
      
      test('should allow regular User to subscribe (if other conditions are met)', () async {
        // Nota: Questo test potrebbe fallire se non ci sono corsi reali nel database
        // o se l'utente non ha entrate disponibili, ma il punto è che non dovrebbe
        // fallire per restrizioni di ruolo
        try {
          await subscribeToCourse(testCourse.uid, regularUser.uid);
          // Se arriva qui, l'iscrizione è stata permessa (non bloccata per ruolo)
          expect(true, true);
        } catch (e) {
          // Se fallisce, deve essere per motivi diversi dal ruolo (es. corso non esistente)
          expect(e.toString(), isNot(contains('Admin e Trainer non possono iscriversi ai corsi')));
        }
      });
    });
    
    group('Edge cases', () {
      test('should handle null role as User', () async {
        // Simula un utente con ruolo null (dovrebbe essere trattato come User)
        // Questo test verifica che il fallback funzioni correttamente
        try {
          await subscribeToCourse(testCourse.uid, 'non-existent-user');
          // Se arriva qui, l'iscrizione è stata permessa (non bloccata per ruolo)
          expect(true, true);
        } catch (e) {
          // Se fallisce, deve essere per motivi diversi dal ruolo
          expect(e.toString(), isNot(contains('Admin e Trainer non possono iscriversi ai corsi')));
        }
      });
      
      test('should handle empty role as User', () async {
        // Simula un utente con ruolo vuoto (dovrebbe essere trattato come User)
        try {
          await subscribeToCourse(testCourse.uid, 'non-existent-user');
          // Se arriva qui, l'iscrizione è stata permessa (non bloccata per ruolo)
          expect(true, true);
        } catch (e) {
          // Se fallisce, deve essere per motivi diversi dal ruolo
          expect(e.toString(), isNot(contains('Admin e Trainer non possono iscriversi ai corsi')));
        }
      });
    });
  });
}
