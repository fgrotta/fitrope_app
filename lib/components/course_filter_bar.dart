import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/course_filters.dart';
import 'package:fitrope_app/utils/course_type_style.dart';
import 'package:fitrope_app/utils/course_types.dart';
import 'package:fitrope_app/utils/sale.dart';
import 'package:flutter/material.dart';

/// Barra filtri della lista corsi: un selettore Tipologia|Sala scambia la
/// dimensione mostrata, e una sola riga di chip resta visibile.
///
/// I filtri delle due dimensioni si combinano comunque in AND, quindi il
/// selettore porta un badge con il numero di selezioni attive: altrimenti un
/// filtro sulla dimensione nascosta continuerebbe a restringere la lista senza
/// che si veda perché.
///
/// Lo stato dei filtri sta nel chiamante: questo widget disegna e notifica.
class CourseFilterBar extends StatelessWidget {
  /// Corsi del giorno selezionato: è la base su cui si calcolano i conteggi.
  final List<Course> courses;
  final Set<String> selectedTypes;
  final Set<String> selectedSale;
  final CourseFilterDimension dimension;
  final ValueChanged<CourseFilterDimension> onDimensionChanged;

  /// Chiamati con la chiave del chip toccato; l'inversione la fa il chiamante.
  final ValueChanged<String> onToggleType;
  final ValueChanged<String> onToggleSala;
  final VoidCallback onClearFilters;

  const CourseFilterBar({
    super.key,
    required this.courses,
    required this.selectedTypes,
    required this.selectedSale,
    required this.dimension,
    required this.onDimensionChanged,
    required this.onToggleType,
    required this.onToggleSala,
    required this.onClearFilters,
  });

  bool get _hasActiveFilters =>
      selectedTypes.isNotEmpty || selectedSale.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) return const SizedBox.shrink();
    final isTipologia = dimension == CourseFilterDimension.tipologia;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDimensionSelector(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...(isTipologia ? _buildTypeChips() : _buildSalaChips()),
              if (_hasActiveFilters)
                TextButton(
                  key: const Key('calendar-clear-filters'),
                  onPressed: onClearFilters,
                  style: TextButton.styleFrom(
                    foregroundColor: primaryColor,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Azzera filtri'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDimensionSelector() {
    Widget segmentLabel(String text, IconData icon, int activeCount) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(text),
            if (activeCount > 0) ...[
              const SizedBox(width: 6),
              _buildFilterBadge(activeCount),
            ],
          ],
        );

    return SegmentedButton<CourseFilterDimension>(
      key: const Key('calendar-filter-dimension'),
      segments: [
        ButtonSegment(
          value: CourseFilterDimension.tipologia,
          label: segmentLabel(
              'Tipologia', Icons.filter_list, selectedTypes.length),
        ),
        ButtonSegment(
          value: CourseFilterDimension.sala,
          label: segmentLabel(
              'Sala', Icons.meeting_room_outlined, selectedSale.length),
        ),
      ],
      selected: {dimension},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onDimensionChanged(selection.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? primaryColor.withValues(alpha: 0.12)
                : null),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? primaryDarkColor
                : onSurfaceVariantColor),
        side: WidgetStateProperty.all(
            const BorderSide(color: outlineVariantColor)),
      ),
    );
  }

  /// Pallino con il numero di filtri attivi su una dimensione.
  Widget _buildFilterBadge(int count) => Container(
        constraints: const BoxConstraints(minWidth: 16),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: primaryColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('$count',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );

  /// Chip a set FISSO: sempre tutte le tipologie di `CourseTypes.all`, anche a
  /// zero corsi. Un elenco che cambia forma ogni giorno impedisce di imparare
  /// dove sta il filtro che si usa sempre.
  List<Widget> _buildTypeChips() {
    final counts = courseTypeCounts(courses, sale: selectedSale);
    return CourseTypes.all.map((type) {
      final count = counts[type.key] ?? 0;
      final selected = selectedTypes.contains(type.key);
      final style = courseTypeStyleForKey(type.key);
      return _buildFilterChip(
        label: type.displayName,
        icon: style.icon,
        color: style.color,
        count: count,
        selected: selected,
        enabled: count > 0 || selected,
        onToggle: () => onToggleType(type.key),
      );
    }).toList();
  }

  List<Widget> _buildSalaChips() {
    final counts = salaCounts(courses, types: selectedTypes);

    Widget chipFor(String key, String label) {
      final count = counts[key] ?? 0;
      final selected = selectedSale.contains(key);
      return _buildFilterChip(
        label: label,
        icon: Icons.meeting_room_outlined,
        color: primaryColor,
        count: count,
        selected: selected,
        enabled: count > 0 || selected,
        onToggle: () => onToggleSala(key),
      );
    }

    return [
      ...Sale.all.map((sala) => chipFor(sala, sala)),
      chipFor(kNoSalaFilterKey, 'Senza sala'),
    ];
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
