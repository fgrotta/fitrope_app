// Anteprima standalone dei mockup della CourseCard (Versioni C, C+ e D).
// Strumento di sviluppo, fuori dall'albero di produzione lib/.
// Avviare con: flutter run -t tool/main_preview.dart
import 'package:flutter/material.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/utils/capacity_color.dart';

void main() => runApp(const PreviewApp());

class CaseData {
  final String label;
  final String description;
  final int subscribed;
  final int capacity;
  const CaseData(this.label, this.description, this.subscribed, this.capacity);
}

const cases = [
  CaseData('Verde — ampia disponibilità',
      '5/20 · 75% posti liberi (≥ 50%) → verde.', 5, 20),
  CaseData('Verde — soglia 50%',
      '10/20 · 50% posti liberi → verde.', 10, 20),
  CaseData('Arancione — disponibilità media',
      '14/20 · 30% posti liberi (tra 15% e 50%) → arancione.', 14, 20),
  CaseData('Rosso — soglia 15%',
      '17/20 · 15% posti liberi (≤ 15%) → rosso.', 17, 20),
  CaseData('Rosso — corso pieno',
      '20/20 · 0% posti liberi → rosso.', 20, 20),
];

const _image = 'assets/course_images/pt_1.webp';

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: const Text('Mockup CourseCard — confronto C+ / C / D'),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Intestazioni di colonna = nomi delle 3 versioni.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _ColHeader('C+', 'Immagine di sfondo'),
                  _ColHeader('C', 'Card blu strutturata'),
                  _ColHeader('D', 'Implementata (sfondo chiaro, lista espandibile)'),
                ],
              ),
              const Divider(height: 24),
              // Una riga per ogni stato: le 3 versioni nello stesso stato.
              for (final c in cases) _stateRow(c),
            ],
          ),
        ),
      ),
    );
  }

  // Riga = uno stato di capienza, con le 3 versioni affiancate.
  Widget _stateRow(CaseData c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.label,
              style: const TextStyle(
                  color: Color(0xFF1A1C1E),
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          Text(c.description,
              style: const TextStyle(color: Color(0xFF5F6368), fontSize: 12)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cell(VariantCPlus(data: c)),
              _cell(VariantC(data: c)),
              _cell(VariantD(data: c)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(Widget card) => Padding(
        padding: const EdgeInsets.only(right: 24),
        child: SizedBox(width: 320, child: card),
      );
}

class _ColHeader extends StatelessWidget {
  final String name;
  final String subtitle;
  const _ColHeader(this.name, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: SizedBox(
        width: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versione $name',
                style: const TextStyle(
                    color: primaryColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            Text(subtitle,
                style: const TextStyle(color: Color(0xFF5F6368), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

Widget metaRow(IconData icon, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: const TextStyle(color: Colors.white))),
      ],
    ),
  );
}

Widget typeChip(String label, Color bg, {Color fg = Colors.white}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

Widget statusPill(int free, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
    child: Text(
      free <= 0 ? 'Pieno' : (free == 1 ? '1 libero' : '$free liberi'),
      style: const TextStyle(
          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

Widget adminIcons({Color? bg}) {
  return Container(
    decoration: BoxDecoration(
      color: bg ?? Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
            icon: const Icon(Icons.edit, size: 18, color: Colors.white),
            onPressed: () {},
            visualDensity: VisualDensity.compact),
        IconButton(
            icon: const Icon(Icons.copy, size: 18, color: Color(0xFFFB8C00)),
            onPressed: () {},
            visualDensity: VisualDensity.compact),
        IconButton(
            icon: const Icon(Icons.delete, size: 18, color: Color(0xFFE53935)),
            onPressed: () {},
            visualDensity: VisualDensity.compact),
      ],
    ),
  );
}

/// MOCKUP VERSIONE C — card blu strutturata: immagine in alto, titolo + metadati
/// a icone, box iscritti con capienza colorata in base ai posti liberi.
class VariantC extends StatelessWidget {
  final CaseData data;
  const VariantC({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final color = capacityColor(data.subscribed, data.capacity);
    final free = data.capacity - data.subscribed;
    final value = data.capacity == 0
        ? 0.0
        : (data.subscribed / data.capacity).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: primaryLightColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 120,
              width: double.infinity,
              child: Image.asset(_image, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: Text('Corso PT',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                      ),
                      adminIcons(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  metaRow(Icons.schedule, '14:37 - 15:37'),
                  metaRow(Icons.person_outline, 'Francesco Trainer'),
                  metaRow(Icons.fitness_center, 'Personal Trainer'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryDarkColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border(left: BorderSide(color: color, width: 4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.groups_outlined,
                                size: 16, color: Colors.white),
                            const SizedBox(width: 6),
                            Text('Iscritti ${data.subscribed}/${data.capacity}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            statusPill(free, color),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 6,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// MOCKUP VERSIONE C+ — immagine come sfondo dell'intera card, contenuto in
/// overlay con scrim; capienza colorata con la stessa regola di C.
class VariantCPlus extends StatelessWidget {
  final CaseData data;
  const VariantCPlus({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final color = capacityColor(data.subscribed, data.capacity);
    final free = data.capacity - data.subscribed;
    final value = data.capacity == 0
        ? 0.0
        : (data.subscribed / data.capacity).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 230,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(_image, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.78),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Text('Corso PT',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(blurRadius: 4, color: Colors.black54)
                                ])),
                      ),
                      typeChip('Personal Trainer', const Color(0xFFF4511E)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  metaRow(Icons.schedule, '14:37 - 15:37'),
                  metaRow(Icons.person_outline, 'Francesco Trainer'),
                  const Spacer(),
                  Row(
                    children: [
                      const Icon(Icons.groups_outlined,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('Iscritti ${data.subscribed}/${data.capacity}',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      statusPill(free, color),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 6,
                      backgroundColor: Colors.white38,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// MOCKUP VERSIONE D — quella IMPLEMENTATA: immagine di sfondo, box iscritti
/// con sfondo chiaro semitrasparente e lista degli iscritti espandibile.
class VariantD extends StatefulWidget {
  final CaseData data;
  const VariantD({super.key, required this.data});

  @override
  State<VariantD> createState() => _VariantDState();
}

class _VariantDState extends State<VariantD> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final color = capacityColor(data.subscribed, data.capacity);
    final free = data.capacity - data.subscribed;
    final value = data.capacity == 0
        ? 0.0
        : (data.subscribed / data.capacity).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: primaryLightColor,
        child: Stack(
          children: [
            Positioned.fill(child: Image.asset(_image, fit: BoxFit.cover)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: Text('Corso PT',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(blurRadius: 4, color: Colors.black54)
                                ])),
                      ),
                      adminIcons(),
                    ],
                  ),
                  metaRow(Icons.schedule, '14:37 - 15:37'),
                  metaRow(Icons.person_outline, 'Francesco Trainer'),
                  metaRow(Icons.fitness_center, 'Personal Trainer'),
                  const SizedBox(height: 10),
                  // Box iscritti: sfondo chiaro semitrasparente, lista espandibile.
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(left: BorderSide(color: color, width: 4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                        'Iscritti (${data.subscribed}/${data.capacity}):',
                                        style: const TextStyle(
                                            color: onPrimaryColor,
                                            fontWeight: FontWeight.bold)),
                                    Icon(
                                        _expanded
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        color: onPrimaryColor,
                                        size: 20),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  statusPill(free, color),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.add,
                                      color: onPrimaryColor, size: 20),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 6,
                            backgroundColor: Colors.black12,
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ),
                        if (_expanded) ...[
                          const SizedBox(height: 6),
                          if (data.subscribed == 0)
                            const Text('Nessun iscritto',
                                style: TextStyle(
                                    color: onPrimaryColor,
                                    fontStyle: FontStyle.italic))
                          else
                            ...List.generate(
                              data.subscribed,
                              (i) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text('• Iscritto ${i + 1}',
                                    style: const TextStyle(
                                        color: onPrimaryColor)),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
