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
          title: const Text('Prototipi calendario mobile'),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _SectionTitle('Filtro corsi del giorno'),
              SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
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
              SizedBox(height: 40),
              _SectionTitle('Visualizzazione mensile'),
              SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
                  _Phone('E — Griglia mensile con pallini',
                      'Griglia del mese con pallini colorati per i corsi; tocca un giorno per vederne i corsi sotto.',
                      VariantMonthGrid(),
                      showMiniCalendar: false),
                  _Phone('F — Agenda mensile',
                      'Lista di tutti i corsi del mese, raggruppati per giorno e ordinati cronologicamente.',
                      VariantMonthAgenda(),
                      showMiniCalendar: false),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: primaryColor, fontSize: 20, fontWeight: FontWeight.bold));
}

/// Cornice "telefono" con un mini-calendario in alto, comune a tutte le varianti.
class _Phone extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool showMiniCalendar;
  const _Phone(this.title, this.subtitle, this.child,
      {this.showMiniCalendar = true});

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
                if (showMiniCalendar) ...[
                  const _MiniCalendar(),
                  const Divider(height: 1),
                ],
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

// ===================== Visualizzazione mensile =====================

// Giugno 2026 con corsi distribuiti su più giorni (il giorno 19 riusa `day`).
const monthCourses = <int, List<MockCourse>>{
  2: [MockCourse('PT Anna', '08:00 - 09:00', CourseType.personal_trainer, 1, 1)],
  4: [
    MockCourse('Functional', '09:00 - 10:00', CourseType.open, 5, 12),
    MockCourse('Cardio', '18:00 - 19:00', CourseType.open, 8, 12),
  ],
  9: [MockCourse('Tabata', '12:30 - 13:30', CourseType.open, 11, 12)],
  11: [
    MockCourse('PT Marco', '10:00 - 11:00', CourseType.personal_trainer, 0, 1),
    MockCourse('Stretching', '19:00 - 20:00', CourseType.open, 3, 12),
  ],
  16: [
    MockCourse('PT Sara', '17:00 - 18:00', CourseType.personal_trainer, 1, 1),
    MockCourse('Functional', '09:00 - 10:00', CourseType.open, 5, 12),
    MockCourse('Cardio', '18:00 - 19:00', CourseType.open, 8, 12),
  ],
  18: [MockCourse('Tabata', '12:30 - 13:30', CourseType.open, 11, 12)],
  19: day, // oggi, giornata piena
  23: [MockCourse('PT Anna', '08:00 - 09:00', CourseType.personal_trainer, 1, 1)],
  25: [MockCourse('Functional', '09:00 - 10:00', CourseType.open, 4, 12)],
  26: [
    MockCourse('Cardio', '18:00 - 19:00', CourseType.open, 8, 12),
    MockCourse('Stretching', '19:00 - 20:00', CourseType.open, 3, 12),
  ],
};

const _giugno2026 = (year: 2026, month: 6, daysInMonth: 30, today: 19);
const _weekdayShort = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];

Widget _monthNavHeader() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(Icons.chevron_left, color: Color(0xFF5F6368)),
          Text('Giugno 2026',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1C1E))),
          Icon(Icons.chevron_right, color: Color(0xFF5F6368)),
        ],
      ),
    );

// ---------- E: griglia mensile con pallini ----------
class VariantMonthGrid extends StatefulWidget {
  const VariantMonthGrid({super.key});
  @override
  State<VariantMonthGrid> createState() => _VariantMonthGridState();
}

class _VariantMonthGridState extends State<VariantMonthGrid> {
  int _selected = _giugno2026.today;

  @override
  Widget build(BuildContext context) {
    final firstWeekday =
        DateTime(_giugno2026.year, _giugno2026.month, 1).weekday; // 1=Lun
    final leading = firstWeekday - 1;
    final cells = leading + _giugno2026.daysInMonth;
    final selectedCourses = monthCourses[_selected] ?? const <MockCourse>[];

    return Column(
      children: [
        _monthNavHeader(),
        Row(
          children: _weekdayShort
              .map((d) => Expanded(
                    child: Center(
                      child: Text(d,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF5F6368))),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.82,
          children: List.generate(cells, (i) {
            if (i < leading) return const SizedBox();
            final day = i - leading + 1;
            final courses = monthCourses[day] ?? const <MockCourse>[];
            final isSelected = day == _selected;
            final isToday = day == _giugno2026.today;
            return GestureDetector(
              onTap: () => setState(() => _selected = day),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isSelected ? primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isToday && !isSelected
                      ? Border.all(color: primaryColor, width: 1.5)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$day',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF1A1C1E))),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 6,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: courses
                            .take(3)
                            .map((c) => Container(
                                  width: 5,
                                  height: 5,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? Colors.white
                                        : capacityColor(
                                            c.subscribed, c.capacity),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        const Divider(height: 1),
        Expanded(
          child: selectedCourses.isEmpty
              ? const Center(
                  child: Text('Nessun corso in questa giornata',
                      style: TextStyle(color: Color(0xFF5F6368))))
              : _list(selectedCourses),
        ),
      ],
    );
  }
}

// ---------- F: agenda mensile ----------
class VariantMonthAgenda extends StatelessWidget {
  const VariantMonthAgenda({super.key});

  @override
  Widget build(BuildContext context) {
    final days = monthCourses.keys.toList()..sort();
    return Column(
      children: [
        _monthNavHeader(),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: days.expand((day) {
              final wd =
                  DateTime(_giugno2026.year, _giugno2026.month, day).weekday;
              return [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
                  child: Text('${_weekdayShort[wd - 1]} $day giugno',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: primaryColor)),
                ),
                ...monthCourses[day]!.map((c) => CourseRow(c)),
              ];
            }).toList(),
          ),
        ),
      ],
    );
  }
}
