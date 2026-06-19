// Anteprima mobile: 4 alternative per filtrare i corsi del giorno per tipologia.
// Strumento di sviluppo. Avviare con: flutter run -t tool/calendar_mobile_preview.dart
import 'package:flutter/material.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/utils/capacity_color.dart';

void main() => runApp(const PreviewApp());

class MockCourse {
  final String name;
  final String time;
  final CourseType type;
  final int subscribed;
  final int capacity;
  const MockCourse(this.name, this.time, this.type, this.subscribed, this.capacity);
}

const day = <MockCourse>[
  MockCourse('PT Anna', '08:00 - 09:00', CourseType.personal_trainer, 1, 1),
  MockCourse('Functional', '09:00 - 10:00', CourseType.open, 5, 12),
  MockCourse('PT Marco', '10:00 - 11:00', CourseType.personal_trainer, 0, 1),
  MockCourse('Tabata', '12:30 - 13:30', CourseType.open, 11, 12),
  MockCourse('PT Sara', '17:00 - 18:00', CourseType.personal_trainer, 1, 1),
  MockCourse('Cardio', '18:00 - 19:00', CourseType.open, 8, 12),
  MockCourse('Stretching', '19:00 - 20:00', CourseType.open, 3, 12),
];

int _count(CourseType t) => day.where((c) => c.type == t).length;

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: primaryColor,
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFFEFEFF4),
        appBar: AppBar(
          title: const Text('Vista mobile corsi — 4 alternative'),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 24,
            runSpacing: 24,
            children: const [
              _Phone('A — Filter chips (sticky)',
                  'Chip Tutti/Open/PT con contatore; filtra la lista. Calendario sempre visibile.',
                  VariantChips()),
              _Phone('B — TabBar',
                  'Una tab per tipologia, contenuto swipeabile. Più app-like ma nasconde le altre.',
                  VariantTabs()),
              _Phone('C — Sezioni collassabili',
                  'Sezioni comprimibili, chiuse di default con contatore: ideale nei giorni pieni.',
                  VariantExpansion()),
              _Phone('D — Segmented control',
                  'Toggle compatto in stile iOS che filtra la lista.',
                  VariantSegmented()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cornice "telefono" con un mini-calendario in alto, comune a tutte le varianti.
class _Phone extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _Phone(this.title, this.subtitle, this.child);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Color(0xFF1A1C1E),
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(color: Color(0xFF5F6368), fontSize: 12.5)),
          const SizedBox(height: 10),
          Container(
            height: 640,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFD0D0D6), width: 6),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: primaryColor,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: const Text('Calendario corsi',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                const _MiniCalendar(),
                const Divider(height: 1),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCalendar extends StatelessWidget {
  const _MiniCalendar();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (i) {
          final selected = i == 3;
          return Container(
            width: 34,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? primaryColor : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(['L', 'M', 'M', 'G', 'V', 'S', 'D'][i],
                    style: TextStyle(
                        fontSize: 11,
                        color: selected ? Colors.white : const Color(0xFF5F6368))),
                Text('${16 + i}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.white : const Color(0xFF1A1C1E))),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Riga corso compatta riusata da tutte le varianti.
class CourseRow extends StatelessWidget {
  final MockCourse c;
  const CourseRow(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = capacityColor(c.subscribed, c.capacity);
    final isPt = c.type == CourseType.personal_trainer;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: const [
          BoxShadow(color: Color(0x11000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        children: [
          Icon(isPt ? Icons.person : Icons.group, size: 20, color: primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E))),
                Text(c.time,
                    style: const TextStyle(color: Color(0xFF5F6368), fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(20)),
            child: Text(capacityPillLabel(c.subscribed, c.capacity),
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

Widget _list(List<MockCourse> items) => ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: items.map((c) => CourseRow(c)).toList(),
    );

// ---------- A: Filter chips ----------
class VariantChips extends StatefulWidget {
  const VariantChips({super.key});
  @override
  State<VariantChips> createState() => _VariantChipsState();
}

class _VariantChipsState extends State<VariantChips> {
  CourseType? _filter; // null = tutti

  @override
  Widget build(BuildContext context) {
    final items = _filter == null ? day : day.where((c) => c.type == _filter).toList();
    Widget chip(String label, CourseType? value) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _filter == value,
            onSelected: (_) => setState(() => _filter = value),
          ),
        );
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              chip('Tutti (${day.length})', null),
              chip('Open (${_count(CourseType.open)})', CourseType.open),
              chip('PT (${_count(CourseType.personal_trainer)})',
                  CourseType.personal_trainer),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _list(items)),
      ],
    );
  }
}

// ---------- B: TabBar ----------
class VariantTabs extends StatelessWidget {
  const VariantTabs({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              labelColor: primaryColor,
              unselectedLabelColor: const Color(0xFF5F6368),
              indicatorColor: primaryColor,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              tabs: [
                Tab(text: 'Tutti (${day.length})'),
                Tab(text: 'Open (${_count(CourseType.open)})'),
                Tab(text: 'PT (${_count(CourseType.personal_trainer)})'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: [
                _list(day),
                _list(day.where((c) => c.type == CourseType.open).toList()),
                _list(day
                    .where((c) => c.type == CourseType.personal_trainer)
                    .toList()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- C: Sezioni collassabili ----------
class VariantExpansion extends StatelessWidget {
  const VariantExpansion({super.key});

  @override
  Widget build(BuildContext context) {
    Widget section(String title, IconData icon, CourseType type) {
      final items = day.where((c) => c.type == type).toList();
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(icon, color: primaryColor),
          title: Text('$title (${items.length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          children: items.map((c) => CourseRow(c)).toList(),
        ),
      );
    }

    return ListView(
      children: [
        section('Personal Trainer', Icons.person, CourseType.personal_trainer),
        const Divider(height: 1),
        section('Open', Icons.group, CourseType.open),
      ],
    );
  }
}

// ---------- D: Segmented control ----------
class VariantSegmented extends StatefulWidget {
  const VariantSegmented({super.key});
  @override
  State<VariantSegmented> createState() => _VariantSegmentedState();
}

class _VariantSegmentedState extends State<VariantSegmented> {
  String _sel = 'all';

  @override
  Widget build(BuildContext context) {
    final items = _sel == 'all'
        ? day
        : day
            .where((c) =>
                c.type ==
                (_sel == 'open' ? CourseType.open : CourseType.personal_trainer))
            .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('Tutti')),
              ButtonSegment(value: 'open', label: Text('Open')),
              ButtonSegment(value: 'pt', label: Text('PT')),
            ],
            selected: {_sel},
            onSelectionChanged: (s) => setState(() => _sel = s.first),
            showSelectedIcon: false,
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _list(items)),
      ],
    );
  }
}
