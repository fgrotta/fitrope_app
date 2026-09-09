import 'package:fitrope_app/components/course_card.dart' show CourseState;
import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';

/// Aspetto del pulsante d'azione di un corso: etichetta, colori e se è
/// cliccabile. È **solo presentazione** — la transazione di iscrizione resta
/// nelle callable, e la gestione dello stato "in corso" nel widget chiamante.
///
/// La gerarchia dei colori: **blu pieno** per ciò che si può fare (iscriversi),
/// **rosso** per ciò che disfa (disiscriversi, uscire dalla lista),
/// **arancione** per la lista d'attesa, **grigio solido** per gli stati che
/// spiegano perché non si può prenotare.
///
/// Sta qui e non dentro `CourseCard` perché la stessa tabella serve anche alla
/// riga compatta dell'agenda: duplicare undici stati in due punti significa
/// vederli divergere alla prima modifica.
class CourseActionStyle {
  final String label;
  final Color background;
  final Color foreground;

  /// `false` per gli stati che spiegano perché non si può prenotare.
  final bool enabled;

  const CourseActionStyle({
    required this.label,
    required this.background,
    required this.foreground,
    required this.enabled,
  });
}

/// `null` per [CourseState.CLOSED]: il corso è passato e il pulsante non va
/// mostrato affatto (non "mostrato e disabilitato").
CourseActionStyle? courseActionStyleFor(CourseState state) {
  switch (state) {
    case CourseState.CLOSED:
      return null;

    case CourseState.CAN_SUBSCRIBE:
      return const CourseActionStyle(
        label: 'Prenotati',
        background: primaryColor,
        foreground: Colors.white,
        enabled: true,
      );
    case CourseState.SUBSCRIBED:
      return const CourseActionStyle(
        label: 'Rimuovi iscrizione',
        background: dangerColor,
        foreground: Colors.white,
        enabled: true,
      );
    case CourseState.CAN_WAITLIST:
      return const CourseActionStyle(
        label: "Lista d'attesa",
        background: Colors.orange,
        foreground: Colors.white,
        enabled: true,
      );
    case CourseState.IN_WAITLIST:
      return const CourseActionStyle(
        label: "Esci dalla lista d'attesa",
        background: dangerColor,
        foreground: Colors.white,
        enabled: true,
      );
    case CourseState.WAITLIST_SPOT_AVAILABLE:
      return const CourseActionStyle(
        label: 'Posto disponibile! Iscriviti ora',
        background: primaryColor,
        foreground: Colors.white,
        enabled: true,
      );

    // Stati bloccanti: stesso trattamento visivo, testo che dice il perché.
    case CourseState.NULL:
      return _blocked('Non disponibile');
    case CourseState.LIMIT:
      return _blocked('Limite entrate settimanali raggiunto');
    case CourseState.FULL:
      return _blocked('Corso pieno');
    case CourseState.SUBSCRIBE_LIMIT:
      return _blocked('Entrate disponibili esaurite');
    case CourseState.EXPIRED:
      return _blocked('Abbonamento scaduto');
  }
}

/// Gli stati bloccanti condividono un grigio **solido**: non invita al tocco,
/// e a differenza di `ghostColor` (40% di opacità) regge sia sul fondo bianco
/// della riga d'agenda sia sulla foto scura della card.
CourseActionStyle _blocked(String label) => CourseActionStyle(
      label: label,
      background: onSurfaceVariantColor,
      foreground: Colors.white,
      enabled: false,
    );
