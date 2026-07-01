// Anteprima: 3 modi per nascondere/collassare il calendario.
// Strumento di sviluppo. Avviare con: flutter run -t tool/calendar_collapse_preview.dart
import 'package:flutter/material.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/utils/capacity_color.dart';

void main() => runApp(const PreviewApp());

class MockCourse {
  final String name;
  final String time;
  final String tag;
  final int subscribed;
  final int capacity;
  const MockCourse(this.name, this.time, this.tag, this.subscribed, this.capacity);
}

// Giugno 2026: 1 giugno = lunedì.
const monthCourses = <int, List<MockCourse>>{
  2: [MockCourse('PT Anna', '08:00 - 09:00', 'Personal Trainer', 1, 1)],
  4: [MockCourse('Functional', '09:00 - 10:00', 'Open', 5, 12),
      MockCourse('Cardio', '18:00 - 19:00', 'Open', 8, 12)],
  9: [MockCourse('Tabata', '12:30 - 13:30', 'Open', 11, 12)],
  11: [MockCourse('PT Marco', '10:00 - 11:00', 'Personal Trainer', 0, 1)],
  16: [MockCourse('PT Sara', '17:00 - 18:00', 'Personal Trainer', 1, 1),
       MockCourse('Functional', '09:00 - 10:00', 'Open', 5, 12)],
  18: [MockCourse('Tabata', '12:30 - 13:30', 'Open', 11, 12)],
  19: [MockCourse('Power Yoga', '10:00 - 11:00', 'Open', 0, 12),
       MockCourse('Stretching', '19:00 - 20:00', 'Open', 3, 12)],
  20: [MockCourse('Power Yoga', '10:00 - 11:00', 'Open', 0, 1),
       MockCourse('Pilates Matwork', '12:00 - 13:00', 'Open', 4, 9),
       MockCourse('Jessica (PT)', '17:00 - 18:00', 'Personal Trainer', 0, 1)],
  23: [MockCourse('PT Anna', '08:00 - 09:00', 'Personal Trainer', 1, 1)],
  25: [MockCourse('Functional', '09:00 - 10:00', 'Open', 4, 12)],
  26: [MockCourse('Cardio', '18:00 - 19:00', 'Open', 8, 12)],
};

const _weekdayShort = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
const _weekdayFull = [
  'Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'
];

String dayLabel(int day) {
  final wd = DateTime(2026, 6, day).weekday; // 1=Lun
  return '${_weekdayFull[wd - 1]} $day giugno';
}

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: primaryColor),
      home: Scaffold(
        backgroundColor: const Color(0xFFEFEFF4),
        appBar: AppBar(
          title: const Text('Nascondere il calendario — 3 prototipi'),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 24,
            runSpacing: 24,
            children: const [
              _Phone('A — Collassabile + navigazione giorno',
                  'Icona calendario per chiudere/aprire. Da chiuso, l\'header giorno ha le frecce ‹ › per cambiare giorno senza riaprire.',
                  VariantA()),
              _Phone('B — Toggle semplice mostra/nascondi',
                  'Chevron sull\'header del mese collassa la griglia. Da chiuso non si cambia giorno: bisogna riaprire.',
                  VariantB()),
              _Phone('C — Striscia settimanale',
                  'Da compatto mostra solo la settimana corrente (una riga); espandi per il mese intero.',
                  VariantC()),
            ],
          ),
        ),
      ),
    );
  }
}

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
                  color: Color(0xFF1A1C1E), fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(color: Color(0xFF5F6368), fontSize: 12.5)),
          const SizedBox(height: 10),
          Container(
            height: 680,
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
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- elementi condivisi ----

Widget courseRow(MockCourse c) {
  final color = capacityColor(c.subscribed, c.capacity);
  final free = c.capacity - c.subscribed;
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border(left: BorderSide(color: color, width: 4)),
      boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 4, offset: Offset(0, 1))],
    ),
    child: Row(
      children: [
        Icon(c.tag == 'Personal Trainer' ? Icons.person : Icons.group,
            size: 20, color: primaryColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E))),
              Text(c.time, style: const TextStyle(color: Color(0xFF5F6368), fontSize: 12)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
          child: Text(free <= 0 ? 'Pieno' : '$free liberi',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

Widget dayList(int day) {
  final courses = monthCourses[day] ?? const <MockCourse>[];
  if (courses.isEmpty) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Nessun corso in questa giornata',
            style: TextStyle(color: Color(0xFF5F6368))),
      ),
    );
  }
  return ListView(
    padding: const EdgeInsets.symmetric(vertical: 6),
    children: courses.map(courseRow).toList(),
  );
}

Widget dayCell(int day, int selected, ValueChanged<int> onSelect) {
  final courses = monthCourses[day] ?? const <MockCourse>[];
  final isSel = day == selected;
  return GestureDetector(
    onTap: () => onSelect(day),
    child: Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isSel ? primaryColor : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$day',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSel ? Colors.white : const Color(0xFF1A1C1E))),
          const SizedBox(height: 2),
          SizedBox(
            height: 5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: courses
                  .take(3)
                  .map((c) => Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSel ? Colors.white : capacityColor(c.subscribed, c.capacity)),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget weekdayRow() => Row(
      children: _weekdayShort
          .map((d) => Expanded(
              child: Center(
                  child: Text(d, style: const TextStyle(fontSize: 11, color: Color(0xFF5F6368))))))
          .toList(),
    );

Widget monthGrid(int selected, ValueChanged<int> onSelect) {
  final leading = DateTime(2026, 6, 1).weekday - 1;
  final cells = leading + 30;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      weekdayRow(),
      const SizedBox(height: 2),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.1,
        children: List.generate(cells, (i) {
          if (i < leading) return const SizedBox();
          return dayCell(i - leading + 1, selected, onSelect);
        }),
      ),
    ],
  );
}

// La settimana (lun-dom) che contiene il giorno selezionato.
List<int> weekOf(int day) {
  final date = DateTime(2026, 6, day);
  final monday = date.subtract(Duration(days: date.weekday - 1));
  return List.generate(7, (i) {
    final d = monday.add(Duration(days: i));
    return d.month == 6 ? d.day : 0; // 0 = fuori giugno (cella vuota)
  });
}

Widget weekRow(int selected, ValueChanged<int> onSelect) {
  return Row(
    children: weekOf(selected)
        .map((d) => Expanded(
            child: d == 0 ? const SizedBox(height: 44) : dayCell(d, selected, onSelect)))
        .toList(),
  );
}

Widget dayHeader(int day, {List<Widget> trailing = const []}) {
  final n = (monthCourses[day] ?? const []).length;
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(dayLabel(day),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E))),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20)),
          child: Text('$n cors${n == 1 ? 'o' : 'i'}',
              style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600, fontSize: 12)),
        ),
        ...trailing,
      ],
    ),
  );
}

// ---------- A: collassabile + navigazione giorno ----------
class VariantA extends StatefulWidget {
  const VariantA({super.key});
  @override
  State<VariantA> createState() => _VariantAState();
}

class _VariantAState extends State<VariantA> {
  int _sel = 20;
  bool _open = true;

  void _shiftDay(int delta) {
    final next = _sel + delta;
    if (next >= 1 && next <= 30) setState(() => _sel = next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Barra di controllo: icona calendario (toggle) + mese + chevron.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(_open ? Icons.calendar_month : Icons.calendar_today,
                    color: primaryColor),
                tooltip: _open ? 'Nascondi calendario' : 'Mostra calendario',
                onPressed: () => setState(() => _open = !_open),
              ),
              const Text('Giugno 2026',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E))),
              const Spacer(),
              // Da chiuso: frecce per cambiare giorno senza riaprire.
              if (!_open) ...[
                IconButton(
                    icon: const Icon(Icons.chevron_left, color: Color(0xFF5F6368)),
                    onPressed: () => _shiftDay(-1)),
                IconButton(
                    icon: const Icon(Icons.chevron_right, color: Color(0xFF5F6368)),
                    onPressed: () => _shiftDay(1)),
              ] else
                IconButton(
                    icon: const Icon(Icons.expand_less, color: Color(0xFF5F6368)),
                    tooltip: 'Nascondi calendario',
                    onPressed: () => setState(() => _open = false)),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: monthGrid(_sel, (d) => setState(() => _sel = d)),
                )
              : const SizedBox(width: double.infinity),
        ),
        const Divider(height: 1),
        dayHeader(_sel),
        const Divider(height: 1),
        Expanded(child: dayList(_sel)),
      ],
    );
  }
}

// ---------- B: toggle semplice ----------
class VariantB extends StatefulWidget {
  const VariantB({super.key});
  @override
  State<VariantB> createState() => _VariantBState();
}

class _VariantBState extends State<VariantB> {
  int _sel = 20;
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Text('Giugno 2026',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E))),
                Icon(_open ? Icons.expand_less : Icons.expand_more, color: const Color(0xFF5F6368)),
                const Spacer(),
                Text(_open ? 'Nascondi' : 'Mostra calendario',
                    style: const TextStyle(color: Color(0xFF5F6368), fontSize: 12)),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: monthGrid(_sel, (d) => setState(() => _sel = d)),
                )
              : const SizedBox(width: double.infinity),
        ),
        const Divider(height: 1),
        dayHeader(_sel),
        const Divider(height: 1),
        Expanded(child: dayList(_sel)),
      ],
    );
  }
}

// ---------- C: striscia settimanale ----------
class VariantC extends StatefulWidget {
  const VariantC({super.key});
  @override
  State<VariantC> createState() => _VariantCState();
}

class _VariantCState extends State<VariantC> {
  int _sel = 20;
  bool _monthExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              const Text('Giugno 2026',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E))),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _monthExpanded = !_monthExpanded),
                icon: Icon(_monthExpanded ? Icons.unfold_less : Icons.unfold_more, size: 18),
                label: Text(_monthExpanded ? 'Settimana' : 'Mese'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: weekdayRow(),
        ),
        const SizedBox(height: 2),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _monthExpanded
                ? GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.1,
                    children: List.generate(DateTime(2026, 6, 1).weekday - 1 + 30, (i) {
                      final leading = DateTime(2026, 6, 1).weekday - 1;
                      if (i < leading) return const SizedBox();
                      return dayCell(i - leading + 1, _sel, (d) => setState(() => _sel = d));
                    }),
                  )
                : weekRow(_sel, (d) => setState(() => _sel = d)),
          ),
        ),
        const Divider(height: 1),
        dayHeader(_sel),
        const Divider(height: 1),
        Expanded(child: dayList(_sel)),
      ],
    );
  }
}
