import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/course_type_style.dart';
import 'package:fitrope_app/utils/sale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Il badge mostra il tag descrittivo o, in sua assenza, il tipo risolto.
Course _course({
  List<String> tags = const [],
  String? sala,
  CourseType courseType = CourseType.open,
}) =>
    Course(
      id: 'c1',
      uid: 'c1',
      name: 'Corso Test',
      startDate: Timestamp.fromDate(DateTime(2026, 6, 9, 10)),
      endDate: Timestamp.fromDate(DateTime(2026, 6, 9, 11)),
      capacity: 10,
      subscribed: 3,
      tags: tags,
      sala: sala,
      courseType: courseType,
    );

Future<void> _pump(WidgetTester tester, Course course,
    {String description = ''}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CourseCard(
          courseId: course.uid,
          course: course,
          title: course.name,
          description: description,
          onRefresh: () {},
        ),
      ),
    ),
  ));
  // Un solo pump: lo stream dell'immagine di sfondo non si stabilizza nel
  // test bundle (stessa scelta di course_card_widget_test.dart).
  await tester.pump();
}

void main() {
  testWidgets('mostra il badge della tipologia ricavata dai tag',
      (tester) async {
    await _pump(tester, _course(tags: [CourseTags.HYROX]));
    expect(find.text('Hyrox'), findsOneWidget);
    expect(find.byIcon(courseTypeStyleForKey(CourseTags.HYROX).icon),
        findsOneWidget);
  });

  testWidgets(
      'un corso Hyrox NON viene etichettato come Open, nonostante '
      'courseType legacy sia open', (tester) async {
    await _pump(
        tester, _course(tags: [CourseTags.HYROX], courseType: CourseType.open));
    expect(find.text('Hyrox'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('Hey Mamma non ricompare nella UI e usa il tipo Open',
      (tester) async {
    await _pump(tester, _course(tags: [CourseTags.HEY_MAMMA]));
    expect(find.text('Hey Mamma'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('un tag V1 sconosciuto conserva il tipo Open', (tester) async {
    await _pump(tester, _course(tags: const ['Sconosciuto']));
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('un corso Open senza tag mostra il tipo', (tester) async {
    await _pump(tester, _course());
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('la sala compare tra i metadati', (tester) async {
    await _pump(tester, _course(tags: [CourseTags.OPEN], sala: Sale.SALA_2),
        description: 'Orario: 10:00 - 11:00\nSala: ${Sale.SALA_2}');
    expect(find.text(Sale.SALA_2), findsOneWidget);
    expect(find.byIcon(Icons.meeting_room_outlined), findsOneWidget);
  });
}
