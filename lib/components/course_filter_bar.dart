import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/course_filters.dart';
import 'package:fitrope_app/utils/course_type_style.dart';
import 'package:fitrope_app/utils/course_types.dart';
import 'package:flutter/material.dart';

/// Barra filtri della lista corsi: una sola riga di chip — "Tutti" più una per
/// tipologia.
///
/// Sotto i 900 px i chip scorrono in orizzontale invece di andare a capo: su
/// mobile lo spazio verticale serve alle card. Da 900 in su restano in un
/// [Wrap], dove stanno comodamente su una riga e lo scroll orizzontale col
/// mouse sarebbe scomodo.
///
/// Non c'è un pulsante "Azzera filtri": ci pensa il chip "Tutti", che è lo
/// stato "nessun filtro" reso visibile. Il pulsante resta solo nell'empty state
/// del filtro, dove è la via d'uscita quando la selezione non lascia passare
/// nulla.
///
/// Lo stato dei filtri sta nel chiamante: questo widget disegna e notifica.
class CourseFilterBar extends StatefulWidget {
  /// Corsi del giorno selezionato: è la base su cui si calcolano i conteggi.
  final List<Course> courses;
  final Set<String> selectedTypes;

  /// Chiamato con la chiave del chip toccato; l'inversione la fa il chiamante.
  final ValueChanged<String> onToggleType;

  /// Chiamato dal chip "Tutti": azzera la selezione.
  final VoidCallback onShowAll;

  const CourseFilterBar({
    super.key,
    required this.courses,
    required this.selectedTypes,
    required this.onToggleType,
    required this.onShowAll,
  });

  @override
  State<CourseFilterBar> createState() => _CourseFilterBarState();
}

class _CourseFilterBarState extends State<CourseFilterBar> {
  late final ScrollController _scroll;

  // Da che lato sfumare: si sfuma solo dove c'è ancora contenuto da scorrere.
  // Partono entrambi a `true` (= nessuna sfumatura) perché prima del primo
  // layout non si sa se ci sia qualcosa da scorrere: meglio nessun gradiente
  // che uno sbagliato per un frame.
  bool _atStart = true;
  bool _atEnd = true;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// `setState` solo se qualcosa cambia davvero: altrimenti ogni frame di
  /// scroll ricostruirebbe la barra.
  void _syncEdges(ScrollMetrics m) {
    final atStart = m.pixels <= m.minScrollExtent;
    final atEnd = m.pixels >= m.maxScrollExtent;
    if (atStart == _atStart && atEnd == _atEnd) return;
    // Le notifiche di metrica arrivano in un microtask, quindi fuori dal frame:
    // il widget può già essere smontato.
    if (!mounted) return;
    setState(() {
      _atStart = atStart;
      _atEnd = atEnd;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.courses.isEmpty) return const SizedBox.shrink();
    final chips = _buildChips();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: isDesktop(context)
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: chips,
            )
          : _buildScrollableRow(chips),
    );
  }

  Widget _buildScrollableRow(List<Widget> chips) {
    return NotificationListener<ScrollMetricsNotification>(
      // Primo layout e resize: la posizione non cambia ma l'estensione sì.
      onNotification: (n) {
        _syncEdges(n.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          _syncEdges(n.metrics);
          return false;
        },
        // `BlendMode.dstIn` maschera l'alfa dei chip, quindi la sfumatura
        // funziona su qualunque sfondo — a differenza di un overlay che sfuma
        // verso un colore fisso. Il mask avvolge lo scroll view, non il Row
        // interno: là dentro il gradiente seguirebbe il contenuto invece di
        // restare ancorato ai bordi visibili.
        child: ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              _atStart ? Colors.white : Colors.transparent,
              Colors.white,
              Colors.white,
              _atEnd ? Colors.white : Colors.transparent,
            ],
            stops: const [0.0, 0.05, 0.95, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  chips[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Chip a set FISSO: "Tutti" e poi sempre tutte le tipologie di
  /// `CourseTypes.all`, anche a zero corsi. Un elenco che cambia forma ogni
  /// giorno impedisce di imparare dove sta il filtro che si usa sempre.
  List<Widget> _buildChips() => [_buildAllChip(), ..._buildTypeChips()];

  /// "Tutti" non è una tipologia: è lo stato "nessun filtro" reso visibile e
  /// toccabile. È selezionato quando il set è vuoto, e toccarlo azzera — quindi
  /// ritoccarlo da selezionato non fa nulla, perché "mostra niente" non esiste.
  /// Il suo conteggio è il totale della giornata, corsi senza tipologia
  /// riconosciuta compresi: sono esattamente le card che si vedono.
  Widget _buildAllChip() => _buildFilterChip(
        label: 'Tutti',
        icon: Icons.apps,
        color: primaryColor,
        count: widget.courses.length,
        selected: widget.selectedTypes.isEmpty,
        enabled: true,
        onToggle: widget.onShowAll,
      );

  List<Widget> _buildTypeChips() {
    final counts = courseTypeCounts(widget.courses);
    return CourseTypes.all.map((type) {
      final count = counts[type.key] ?? 0;
      final selected = widget.selectedTypes.contains(type.key);
      final style = courseTypeStyleForKey(type.key);
      return _buildFilterChip(
        label: type.displayName,
        icon: style.icon,
        color: style.color,
        count: count,
        selected: selected,
        enabled: count > 0 || selected,
        onToggle: () => widget.onToggleType(type.key),
      );
    }).toList();
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required Color color,
    required int count,
    required bool selected,
    required bool enabled,
    required VoidCallback onToggle,
  }) {
    final Color contentColor = !enabled
        ? onSurfaceVariantColor.withValues(alpha: 0.45)
        : (selected ? Colors.white : onSurfaceColor);

    return FilterChip(
      key: Key('calendar-filter-chip-$label'),
      avatar: Icon(icon, size: 16, color: selected ? Colors.white : color),
      label: Text.rich(TextSpan(children: [
        TextSpan(text: label),
        TextSpan(
          text: '  $count',
          style: TextStyle(
            color:
                selected ? Colors.white70 : contentColor.withValues(alpha: 0.7),
            fontWeight: FontWeight.bold,
          ),
        ),
      ])),
      selected: selected,
      showCheckmark: false,
      // Un chip selezionato non viene MAI disabilitato: cambiando giorno
      // resterebbe attivo su un conteggio 0 e non sarebbe più deselezionabile.
      onSelected: enabled ? (_) => onToggle() : null,
      selectedColor: color,
      backgroundColor: backgroundColor,
      disabledColor: surfaceVariantColor,
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: contentColor,
      ),
      side: BorderSide(
          color: selected
              ? color
              : (enabled
                  ? outlineVariantColor
                  : outlineVariantColor.withValues(alpha: 0.5))),
      visualDensity: VisualDensity.compact,
    );
  }
}
