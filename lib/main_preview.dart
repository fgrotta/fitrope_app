// File temporaneo di anteprima per verificare la CourseCard reale (versione C+).
// Non fa parte dell'app: avviare con `flutter run -t lib/main_preview.dart`.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/types/fitropeUser.dart';

void main() => runApp(const PreviewApp());

List<FitropeUser> mockUsers(int n) => List.generate(
      n,
      (i) => FitropeUser(
        uid: 'u$i',
        name: 'Iscritto',
        lastName: '${i + 1}',
        email: 'u$i@example.com',
        courses: const [],
        role: 'User',
        createdAt: DateTime(2026, 1, 1),
      ),
    );

class CaseData {
  final String label;
  final String description;
  final int subscribed;
  final int capacity;
  final CourseType type;
  const CaseData(
      this.label, this.description, this.subscribed, this.capacity, this.type);
}

const cases = [
  CaseData('Verde — ampia disponibilità',
      '2/8 · 75% posti liberi (≥ 50%) → verde.', 2, 8, CourseType.personal_trainer),
  CaseData('Verde — soglia 50%',
      '4/8 · 50% posti liberi → verde.', 4, 8, CourseType.open),
  CaseData('Arancione — disponibilità media',
      '6/8 · 25% posti liberi (tra 15% e 50%) → arancione.', 6, 8, CourseType.personal_trainer),
  CaseData('Rosso — quasi pieno',
      '7/8 · 12,5% posti liberi (≤ 15%) → rosso.', 7, 8, CourseType.open),
  CaseData('Rosso — corso pieno',
      '8/8 · 0% posti liberi → rosso.', 8, 8, CourseType.personal_trainer),
];

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});

  Course _course(CaseData c) => Course(
        id: 'c',
        uid: 'c',
        name: c.type == CourseType.personal_trainer
            ? 'Corso PT'
            : 'Functional Training',
        startDate: Timestamp.fromDate(DateTime(2026, 6, 9, 18, 0)),
        endDate: Timestamp.fromDate(DateTime(2026, 6, 9, 19, 0)),
        capacity: c.capacity,
        subscribed: c.subscribed,
        courseType: c.type,
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: const Text('CourseCard reale — Versione C+ · casi capienza'),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 24,
            runSpacing: 28,
            alignment: WrapAlignment.start,
            children: cases.map(_card).toList(),
          ),
        ),
      ),
    );
  }

  Widget _card(CaseData c) {
    final course = _course(c);
    final tipologia = c.type.label;
    final name = course.name;
    return SizedBox(
      width: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CourseCard(
            courseId: 'c',
            course: course,
            title: name,
            description:
                'Orario: 18:00 - 19:00\nTrainer: Francesco Trainer\nTipologia: $tipologia',
            capacity: c.capacity,
            subscribed: c.subscribed,
            subscribersUsers: mockUsers(c.subscribed),
            waitlistUsers: const [],
            showClickableSubscribers: true,
            isAdmin: true,
            userRole: 'Admin',
            onEdit: () {},
            onDuplicate: () {},
            onDelete: () {},
            onRefresh: () {},
          ),
          const SizedBox(height: 12),
          Text(c.label,
              style: const TextStyle(
                  color: Color(0xFF1A1C1E),
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(c.description,
              style: const TextStyle(
                  color: Color(0xFF5F6368), fontSize: 13, height: 1.35)),
        ],
      ),
    );
  }
}
