import 'package:flutter/material.dart';

/// Durata dell'**apertura**.
///
/// Tarata sulla POC (variante "A2 · Zoom dalla riga"). Vive in una costante
/// sola perché è il numero che più probabilmente verrà ritoccato a occhio.
const Duration kCourseTileAnimationDuration = Duration(milliseconds: 320);

/// Durata della **chiusura**: l'inversa dell'apertura, un po' più rapida.
/// Chi chiude ha già visto la card e vuole tornare alla lista: farlo aspettare
/// quanto all'apertura fa sembrare l'interfaccia lenta.
const Duration kCourseTileCloseDuration = Duration(milliseconds: 240);

/// Decelera in fondo: il movimento "si posa" invece di fermarsi di colpo.
const Curve kCourseTileAnimationCurve = Cubic(0.22, 0.61, 0.36, 1.0);

/// Scala di partenza della card. Non parte da zero: il salto 0→1 legge come un
/// elemento che compare, non come la riga che si gonfia.
const double kCourseTileCardStartScale = 0.94;

/// Tile del calendario che passa dalla **riga compatta** alla **card grande**
/// trasformandosi, non aprendo un secondo blocco sotto di sé.
///
/// L'animazione è la variante "A2 · Zoom dalla riga" scelta in POC: la card
/// entra scalando **dal vertice in alto a sinistra**, l'unico punto che i due
/// stati hanno in comune, mentre l'altezza va da quella della riga a quella
/// della card. È l'origine condivisa a far leggere il passaggio come una
/// trasformazione. La chiusura ripercorre la stessa strada al contrario, in
/// [kCourseTileCloseDuration].
///
/// **Perché un AnimationController e non le animazioni implicite.** In
/// chiusura la card deve restare montata mentre esce, e nello stesso momento
/// deve essere la riga a dettare l'altezza — quindi i due layer si scambiano di
/// posto nello `Stack`. Cambiando slot, un `AnimatedScale`/`AnimatedOpacity`
/// viene ricostruito e perde lo stato: l'animazione non parte (bug preso dai
/// test di questo file). I valori calcolati da un controller esplicito, invece,
/// sopravvivono a qualunque rebuild.
class ExpandableCourseTile extends StatefulWidget {
  final bool expanded;

  /// Stato chiuso: la riga d'agenda.
  final Widget collapsed;

  /// Stato aperto: la card con la foto.
  final Widget expandedChild;

  /// Chiamata toccando la card aperta. Serve perché aprendo la riga sparisce:
  /// senza questo non ci sarebbe modo di tornare alla lista.
  ///
  /// Il tocco NON viene rubato ai pulsanti dentro la card: nell'arena dei
  /// gesti vincono loro sulla propria area, quindi "Prenotati" prenota e il
  /// resto della card chiude.
  final VoidCallback? onCollapse;

  final Duration duration;
  final Duration closeDuration;

  const ExpandableCourseTile({
    super.key,
    required this.expanded,
    required this.collapsed,
    required this.expandedChild,
    this.onCollapse,
    this.duration = kCourseTileAnimationDuration,
    this.closeDuration = kCourseTileCloseDuration,
  });

  @override
  State<ExpandableCourseTile> createState() => _ExpandableCourseTileState();
}

class _ExpandableCourseTileState extends State<ExpandableCourseTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curved;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: widget.closeDuration,
      value: widget.expanded ? 1 : 0,
    );
    _curved = CurvedAnimation(
      parent: _controller,
      curve: kCourseTileAnimationCurve,
      reverseCurve: kCourseTileAnimationCurve.flipped,
    );
  }

  @override
  void didUpdateWidget(ExpandableCourseTile old) {
    super.didUpdateWidget(old);
    _controller.duration = widget.duration;
    _controller.reverseDuration = widget.closeDuration;
    if (widget.expanded != old.expanded) {
      widget.expanded ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, _) {
        final t = _curved.value;

        // A regime chiuso la card non sta nemmeno nell'albero: una lista di
        // corsi non deve tenere in memoria una card per riga.
        if (t == 0) {
          return AnimatedSize(
            duration: widget.closeDuration,
            curve: kCourseTileAnimationCurve,
            alignment: Alignment.topCenter,
            child: widget.collapsed,
          );
        }

        final closing = _controller.status == AnimationStatus.reverse;
        final card = _card(t, interactive: !closing);

        return AnimatedSize(
          // In chiusura l'altezza deve rientrare col ritmo della chiusura.
          duration: closing ? widget.closeDuration : widget.duration,
          curve: kCourseTileAnimationCurve,
          alignment: Alignment.topCenter,
          child: Stack(
            alignment: Alignment.topLeft,
            clipBehavior: Clip.hardEdge,
            children: closing
                // Chiudendo è la riga a dettare l'altezza, così AnimatedSize
                // la riporta giù; la card le passa sopra mentre si ritira.
                ? [
                    widget.collapsed,
                    Positioned(top: 0, left: 0, right: 0, child: card),
                  ]
                // Aprendo e da aperta comanda la card.
                : [card],
          ),
        );
      },
    );
  }

  Widget _card(double t, {required bool interactive}) {
    final scale =
        kCourseTileCardStartScale + (1 - kCourseTileCardStartScale) * t;
    Widget child = widget.expandedChild;
    if (interactive && widget.onCollapse != null) {
      child = GestureDetector(
        key: const Key('tile-card-collapse'),
        onTap: widget.onCollapse,
        child: child,
      );
    }
    return IgnorePointer(
      ignoring: !interactive,
      child: Opacity(
        key: const Key('tile-card-opacity'),
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: child,
        ),
      ),
    );
  }
}
