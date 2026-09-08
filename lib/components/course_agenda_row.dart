import 'package:fitrope_app/components/course_card.dart' show CourseState;
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/capacity_color.dart';
import 'package:fitrope_app/utils/course_action_style.dart';
import 'package:fitrope_app/utils/course_images.dart';
import 'package:fitrope_app/utils/course_type_style.dart';
import 'package:fitrope_app/utils/get_course_time_range.dart';
import 'package:flutter/material.dart';

/// Riga compatta di un corso nell'agenda: è lo stato **chiuso** della tile
/// espandibile del calendario.
///
/// Mostra quel che serve a scegliere una lezione — orario, miniatura, nome,
/// tipologia, sala, trainer, posti e azione — e nulla di più: il dettaglio con
/// la foto grande arriva espandendo (vedi `ExpandableCourseTile`).
///
/// L'azione **non** propaga il tocco alla riga: "Prenotati" prenota, non apre.
class CourseAgendaRow extends StatelessWidget {
  final Course course;
  final CourseState courseState;
  final String trainerName;

  /// Tocco sulla riga: apre il dettaglio.
  final VoidCallback onTap;

  /// Tocco sull'azione (iscrizione, waitlist, disiscrizione).
  final VoidCallback onAction;

  /// `true` mentre la callable dell'azione è in volo: blocca il doppio invio.
  final bool isProcessing;

  const CourseAgendaRow({
    super.key,
    required this.course,
    required this.courseState,
    required this.trainerName,
    required this.onTap,
    required this.onAction,
    this.isProcessing = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = courseTypeStyleForTags(course.tags);
    final action = courseActionStyleFor(courseState);
    final uid = course.uid;

    // Da 900px la riga si distende su una linea sola: la meta prende una
    // colonna propria accanto al titolo e posti/azione stanno affiancati.
    // Impilandoli come su mobile restava un vuoto enorme in mezzo alla riga.
    final wide = isDesktop(context);

    return InkWell(
      key: Key('agenda-row-$uid'),
      onTap: onTap,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: outlineVariantColor)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Accento della tipologia: la stessa lettura a colpo d'occhio della
            // card, in 4px.
            Container(
              key: Key('agenda-row-accent-$uid'),
              width: 4,
              height: wide ? 52 : 64,
              color: style.color,
            ),
            const SizedBox(width: 10),
            _buildTime(wide),
            const SizedBox(width: 10),
            _buildThumb(uid),
            const SizedBox(width: 10),
            if (wide) ...[
              Expanded(flex: 3, child: _buildTitle()),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: _buildMeta(style)),
              const SizedBox(width: 10),
              _buildPill(),
              const SizedBox(width: 8),
              // Larghezza FISSA: con `auto` la colonna cambierebbe misura col
              // testo del pulsante ("Prenotati" vs "Rimuovi iscrizione") e le
              // colonne precedenti ballerebbero da una riga all'altra.
              SizedBox(width: 168, child: _buildAction(action, uid)),
            ] else ...[
              Expanded(child: _buildTitleAndMeta(style)),
              const SizedBox(width: 8),
              _buildTrailing(action, uid),
            ],
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  /// La colonna orario è la spina dell'agenda: larghezza fissa, così i nomi dei
  /// corsi partono tutti dalla stessa ascissa e la lista si scorre a occhio.
  /// Su mobile va su due righe per non rubare larghezza al titolo; su desktop
  /// ci sta per esteso.
  Widget _buildTime(bool wide) {
    if (wide) {
      return SizedBox(
        width: 104,
        child: Text(
          getCourseTimeRange(course),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: onSurfaceColor),
        ),
      );
    }
    final range = getCourseTimeRange(course).split(' - ');
    return SizedBox(
      width: 42,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(range.first,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: onSurfaceColor)),
          if (range.length > 1)
            Text(range.last,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: onSurfaceVariantColor)),
        ],
      ),
    );
  }

  /// Miniatura con il chevron nell'angolo: l'affordance di apertura sta qui e
  /// non in una colonna propria, che costerebbe larghezza al titolo — ed è
  /// proprio l'elemento che espandendo diventa la foto grande.
  Widget _buildThumb(String uid) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                CourseImages.getCourseImage(course),
                fit: BoxFit.cover,
                cacheWidth: 132, // 44px @3x: non serve decodificare di più
                errorBuilder: (_, __, ___) =>
                    const ColoredBox(color: surfaceVariantColor),
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              key: Key('agenda-row-chevron-$uid'),
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                color: onSurfaceColor.withValues(alpha: 0.65),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.expand_more, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleAndMeta(CourseTypeStyle style) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitle(),
          const SizedBox(height: 2),
          _buildMeta(style),
        ],
      );

  /// Il titolo tronca, non va a capo: l'altezza della riga resta costante e la
  /// lista non "balla" da un corso all'altro.
  Widget _buildTitle() => Text(
        course.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 14.5, fontWeight: FontWeight.w700, color: onSurfaceColor),
      );

  /// Una riga sola di metadati, troncata: tipologia (col colore che la card
  /// ripete), sala, trainer.
  Widget _buildMeta(CourseTypeStyle style) => Row(
        children: [
          Icon(style.icon, size: 13, color: style.color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${course.sala ?? 'Nessuna sala'} · $trainerName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 12, color: onSurfaceVariantColor),
            ),
          ),
        ],
      );

  /// Su mobile pill sopra e azione sotto: in verticale ci stanno entrambe senza
  /// rubare larghezza al titolo.
  Widget _buildTrailing(CourseActionStyle? action, String uid) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildPill(),
          if (action != null) ...[
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: _buildAction(action, uid),
            ),
          ],
        ],
      );

  Widget _buildPill() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: capacityColor(course.subscribed, course.capacity),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          capacityPillLabel(course.subscribed, course.capacity),
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );

  Widget _buildAction(CourseActionStyle? action, String uid) {
    if (action == null) return const SizedBox.shrink();
    return ElevatedButton(
      key: Key('agenda-row-action-$uid'),
      onPressed: action.enabled && !isProcessing ? onAction : null,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(action.background),
        minimumSize: WidgetStateProperty.all(Size.zero),
        padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
      ),
      child: Text(
        action.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
            color: action.foreground,
            fontSize: 11.5,
            fontWeight: FontWeight.w700),
      ),
    );
  }
}
