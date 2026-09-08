import 'package:flutter/material.dart';

/// Durata della transizione riga ↔ card.
///
/// Tarata sulla POC (variante "A2 · Zoom dalla riga"). Vive in una costante
/// sola perché è il numero che più probabilmente verrà ritoccato a occhio dopo
/// averlo visto sull'app vera.
const Duration kCourseTileAnimationDuration = Duration(milliseconds: 320);

/// Decelera in fondo: l'apertura "si posa" invece di fermarsi di colpo.
const Curve kCourseTileAnimationCurve = Cubic(0.22, 0.61, 0.36, 1.0);

/// Scala di partenza della card. Non parte da zero: il salto 0→1 legge come un
/// elemento che compare, non come la riga che si gonfia.
const double kCourseTileCardStartScale = 0.94;

/// Tile del calendario che passa dalla **riga compatta** alla **card grande**
/// trasformandosi, non aprendo un secondo blocco sotto di sé.
///
/// L'animazione è la variante "A2 · Zoom dalla riga" scelta in POC: la card
/// entra scalando **dal vertice in alto a sinistra**, che è l'unico punto che i
/// due stati hanno in comune, mentre [AnimatedSize] porta l'altezza da quella
/// della riga a quella della card. È l'origine condivisa a far leggere il
/// passaggio come una trasformazione: la prima versione impilava i due stati in
/// verticale e sembrava che si aprisse *un'altra* riga.
///
/// **Un solo layer per volta.** Tenerli entrambi in uno `Stack` e scambiarne lo
/// slot a seconda di chi dimensiona faceva ricostruire l'albero del layer
/// entrante, e l'animazione non partiva affatto (bug preso da
/// `expandable_course_tile_test.dart`). Con un figlio solo la card viene
/// montata al momento dell'apertura e la sua animazione parte davvero.
class ExpandableCourseTile extends StatelessWidget {
  final bool expanded;

  /// Stato chiuso: la riga d'agenda.
  final Widget collapsed;

  /// Stato aperto: la card con la foto.
  final Widget expandedChild;

  final Duration duration;

  const ExpandableCourseTile({
    super.key,
    required this.expanded,
    required this.collapsed,
    required this.expandedChild,
    this.duration = kCourseTileAnimationDuration,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: duration,
      curve: kCourseTileAnimationCurve,
      alignment: Alignment.topCenter,
      child: expanded
          ? _ZoomFromTopLeft(
              key: const Key('tile-card'),
              duration: duration,
              child: expandedChild,
            )
          : KeyedSubtree(key: const Key('tile-row'), child: collapsed),
    );
  }
}

/// Entra scalando dal vertice in alto a sinistra, con l'opacità agganciata
/// **allo stesso avanzamento** della scala: due animazioni separate sulla
/// stessa transizione finiscono per sfasarsi.
class _ZoomFromTopLeft extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const _ZoomFromTopLeft({
    super.key,
    required this.child,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: kCourseTileCardStartScale, end: 1),
      duration: duration,
      curve: kCourseTileAnimationCurve,
      builder: (context, scale, child) {
        final progress = ((scale - kCourseTileCardStartScale) /
                (1 - kCourseTileCardStartScale))
            .clamp(0.0, 1.0);
        return Opacity(
          key: const Key('tile-card-opacity'),
          opacity: progress,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
