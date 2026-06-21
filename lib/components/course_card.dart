import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/capacity_color.dart';
import 'package:fitrope_app/utils/course_images.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/courses/subscribeToCourse.dart';
import 'package:fitrope_app/api/courses/deleteCourse.dart';
import 'package:fitrope_app/api/courses/updateCourseSubscribedCount.dart';
import 'package:fitrope_app/api/courses/leaveWaitlist.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/types/course.dart';

enum CourseState {
  NULL,
  EXPIRED,
  CAN_SUBSCRIBE,
  FULL,
  SUBSCRIBED,
  LIMIT,
  SUBSCRIBE_LIMIT,
  CLOSED,
  CAN_WAITLIST,
  IN_WAITLIST,
  WAITLIST_SPOT_AVAILABLE,
}

class CourseCard extends StatefulWidget {
  final String courseId;
  final Course course;
  final String title;
  final TextStyle? titleStyle;
  final String description;
  final TextStyle? descriptionStyle;
  final Function? onClick;
  final Function? onClickAction;
  final CourseState courseState;
  final int? capacity;
  final int? subscribed;
  final List<String>? subscribersNames;
  final List<FitropeUser>? subscribersUsers;
  final List<FitropeUser>? waitlistUsers;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback onRefresh; // Callback per aggiornare la lista
  final bool isAdmin;
  final String? userRole; // Ruolo dell'utente corrente
  final bool
      showClickableSubscribers; // Se true, mostra la lista cliccabile invece del dialog

  const CourseCard({
    required this.courseId,
    required this.course,
    super.key,
    required this.title,
    this.courseState = CourseState.NULL,
    this.titleStyle,
    this.description = "",
    this.descriptionStyle,
    this.onClick,
    this.onClickAction,
    this.capacity,
    this.subscribed,
    this.subscribersNames,
    this.subscribersUsers,
    this.waitlistUsers,
    this.onDuplicate,
    this.onDelete,
    this.onEdit,
    required this.onRefresh,
    this.isAdmin = false,
    this.userRole,
    this.showClickableSubscribers = false,
  });

  @override
  State<CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<CourseCard> {
  bool _isProcessing = false;
  bool _subscribersExpanded = false; // lista iscritti collassata di default

  // Colore della lista d'attesa: blu accento (come i marker del calendario)
  // invece dell'arancione, per restare leggibile anche sopra le immagini di
  // sfondo dal tono caldo, dove l'arancione si confondeva.
  static const Color _waitlistColor = Color.fromARGB(255, 37, 99, 235);

  void showSubscribersDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        title: const Text('Iscritti al corso'),
        content:
            widget.subscribersNames == null || widget.subscribersNames!.isEmpty
                ? const Text('Nessun iscritto')
                : SizedBox(
                    width: 300,
                    child: ListView(
                      shrinkWrap: true,
                      children: widget.subscribersNames!
                          .map((name) => ListTile(title: Text(name)))
                          .toList(),
                    ),
                  ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Chiudi',
              style: TextStyle(color: onPrimaryColor),
            ),
          ),
        ],
      ),
    );
  }

  void showDeleteConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        title: const Text('Elimina Corso'),
        content: Text(
            'Sei sicuro di voler eliminare il corso "${widget.title}"?\n\nQuesta azione eliminerà anche tutte le iscrizioni al corso.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Annulla',
              style: TextStyle(color: onPrimaryColor),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (widget.onDelete != null) {
                widget.onDelete!();
              }
            },
            child: const Text('Elimina', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showUserDetails(BuildContext context, FitropeUser user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserDetailPage(user: user),
      ),
    );
  }

  void _showAddSubscriberDialog(BuildContext context) async {
    final result = await showDialog(
      context: context,
      builder: (context) => AddSubscriberDialog(
        courseId: widget.courseId,
        courseName: widget.title,
        existingSubscribers: widget.subscribersUsers ?? [],
        capacity: widget.capacity ?? 0,
      ),
    );

    // Se è stato aggiunto un utente, aggiorna la lista
    if (result == true) {
      widget.onRefresh();
    }
  }

  void _showRemoveUserConfirmationDialog(
      BuildContext context, FitropeUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        title: const Text('Rimuovi Iscrizione'),
        content: Text(
            'Sei sicuro di voler rimuovere ${user.name} ${user.lastName} dal corso "${widget.title}"?\n\n'
            'L\'utente riceverà il rimborso del credito se ha un pacchetto entrate.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Annulla',
              style: TextStyle(color: onPrimaryColor),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rimuovi', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await removeUserFromCourse(widget.courseId, user.uid);
        SnackBarUtils.showSuccessSnackBar(
          context,
          'Utente rimosso con successo dal corso',
        );
        // Aggiorna la lista
        widget.onRefresh();
      } catch (e) {
        SnackBarUtils.showErrorSnackBar(
          context,
          'Errore durante la rimozione: ${e.toString()}',
        );
      }
    }
  }

  // Funzione per verificare se il numero di iscritti effettivi differisce dal valore nel corso
  bool _hasEnrollmentMismatch() {
    if (widget.subscribersUsers == null || widget.subscribed == null) {
      return false;
    }
    return widget.subscribersUsers!.length != widget.subscribed!;
  }

  // Mostra il dialog per correggere il conteggio degli iscritti
  void _showCorrectCountDialog(BuildContext context) {
    if (widget.subscribersUsers == null || widget.subscribed == null) return;

    int actualCount = widget.subscribersUsers!.length;
    int storedCount = widget.subscribed!;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: backgroundColor,
          title: const Text('Correggi Conteggio Iscritti'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'È stata rilevata una discrepanza nel conteggio degli iscritti:',
                style: TextStyle(color: onPrimaryColor),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conteggio attuale nel database: $storedCount',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Numero effettivo di iscritti: $actualCount',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Vuoi aggiornare il conteggio nel database con il numero effettivo di iscritti?',
                style: TextStyle(color: onPrimaryColor),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla',
                  style: TextStyle(color: onPrimaryColor)),
            ),
            ElevatedButton(
              onPressed: () => _correctSubscribedCount(context, actualCount),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child:
                  const Text('Correggi', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // Corregge il conteggio degli iscritti nel database
  Future<void> _correctSubscribedCount(
      BuildContext context, int newCount) async {
    try {
      Navigator.pop(context); // Chiudi il dialog

      await updateCourseSubscribedCount(widget.courseId, newCount).then((_) {
        widget.onRefresh();
      });

      // Mostra messaggio di successo
      SnackBarUtils.showSuccessSnackBar(
        context,
        'Conteggio iscritti aggiornato con successo!',
      );
    } catch (e) {
      SnackBarUtils.showErrorSnackBar(
        context,
        'Errore durante l\'aggiornamento: ${e.toString()}',
      );
    }
  }

  Widget _buildClickableSubscribersList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header tappabile: espande/collassa la lista degli iscritti.
        Semantics(
          button: true,
          expanded: _subscribersExpanded,
          label:
              'Iscritti ${widget.subscribersUsers!.length} di ${widget.capacity}',
          hint: _subscribersExpanded
              ? 'Tocca per nascondere la lista iscritti'
              : 'Tocca per mostrare la lista iscritti',
          child: InkWell(
            onTap: () =>
                setState(() => _subscribersExpanded = !_subscribersExpanded),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          'Iscritti (${widget.subscribersUsers!.length}/${widget.capacity}):',
                          style: const TextStyle(
                              color: onPrimaryColor,
                              fontWeight: FontWeight.bold)),
                      Icon(
                        _subscribersExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: onPrimaryColor,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                // Icona + per aggiungere iscritti (solo per Admin)
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (widget.capacity != null && widget.capacity! > 0)
                    _capacityPill(
                        widget.subscribersUsers!.length, widget.capacity!),
                  if (widget.isAdmin)
                    IconButton(
                      icon: const Icon(Icons.add,
                          color: onPrimaryColor, size: 20),
                      onPressed: () => _showAddSubscriberDialog(context),
                      tooltip: 'Aggiungi iscritto',
                    ),
                  if (_hasEnrollmentMismatch())
                    IconButton(
                      icon: const Icon(Icons.sync_problem,
                          color: Colors.red, size: 20),
                      onPressed: () => _showCorrectCountDialog(context),
                      tooltip: 'Correggi conteggio iscritti',
                    ),
                ])
              ],
            ),
          ),
        ),
        if (widget.capacity != null && widget.capacity! > 0) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (widget.subscribersUsers!.length / widget.capacity!)
                  .clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.black12,
              // Rende la barra leggibile dagli screen reader. Il valore
              // resta quello percentuale di default (deve essere numerico);
              // l'informazione sui posti liberi va nella label.
              semanticsLabel:
                  'Capienza corso, ${capacityPillLabel(widget.subscribersUsers!.length, widget.capacity!)}',
              valueColor: AlwaysStoppedAnimation<Color>(
                capacityColor(
                    widget.subscribersUsers!.length, widget.capacity!),
              ),
            ),
          ),
        ],
        // Lista nomi visibile solo quando espansa.
        if (_subscribersExpanded) ...[
          const SizedBox(height: 6),
          if (widget.subscribersUsers!.isEmpty)
            const Text('Nessun iscritto',
                style: TextStyle(
                    color: onPrimaryColor, fontStyle: FontStyle.italic)),
          ...widget.subscribersUsers!.map((user) {
            String displayName = getDisplayName(user);
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showUserDetails(context, user),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text(
                          '• $displayName',
                          style: const TextStyle(
                            color: onPrimaryColor,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Pulsante di rimozione per admin/trainer
                  if (widget.isAdmin || widget.userRole == 'Trainer')
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          color: Colors.red, size: 16),
                      onPressed: () =>
                          _showRemoveUserConfirmationDialog(context, user),
                      tooltip: 'Rimuovi iscrizione',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildWaitlistUsersList(BuildContext context) {
    if (!_subscribersExpanded ||
        widget.waitlistUsers == null ||
        widget.waitlistUsers!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Lista d\'attesa (${widget.waitlistUsers!.length}):',
          style: const TextStyle(
              color: _waitlistColor, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        ...widget.waitlistUsers!.map((user) {
          String displayName = getDisplayName(user);
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showUserDetails(context, user),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text(
                        '• $displayName',
                        style: const TextStyle(
                          color: _waitlistColor,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.isAdmin || widget.userRole == 'Trainer')
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.red, size: 16),
                    onPressed: () => _removeFromWaitlist(context, user),
                    tooltip: 'Rimuovi dalla lista d\'attesa',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  void _removeFromWaitlist(BuildContext context, FitropeUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        title: const Text('Rimuovi dalla lista d\'attesa'),
        content: Text(
            'Sei sicuro di voler rimuovere ${user.name} ${user.lastName} dalla lista d\'attesa di "${widget.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Annulla', style: TextStyle(color: onPrimaryColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rimuovi', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      try {
        await leaveWaitlist(widget.courseId, user.uid);

        if (!mounted) return;

        SnackBarUtils.showSuccessSnackBar(
          context,
          'Utente rimosso dalla lista d\'attesa',
        );
        widget.onRefresh();
      } catch (e) {
        if (!mounted) return;

        SnackBarUtils.showErrorSnackBar(
          context,
          'Errore durante la rimozione: ${e.toString()}',
        );
      }
    }
  }

  String getDisplayName(FitropeUser user) {
    // Usa la stessa logica di UserDisplayUtils per coerenza
    // Questa funzione è chiamata solo per admin/trainer (showClickableSubscribers = true)
    String baseName = '${user.name} ${user.lastName}';

    if (user.isAnonymous) {
      return '$baseName - (Anonimo)';
    }
    if (user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_PROVA) {
      return '$baseName - (Prova)';
    }
    return baseName;
  }

  Widget renderTitle() {
    if (widget.titleStyle != null) {
      return Text(
        widget.title,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: widget.titleStyle,
      );
    }

    return Text(
      widget.title,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
      ),
    );
  }

  // Alternativa C: icona associata a ciascuna riga di metadati.
  IconData _iconForMeta(String label) {
    switch (label.toLowerCase()) {
      case 'orario':
        return Icons.schedule;
      case 'trainer':
        return Icons.person_outline;
      case 'tipologia':
        return Icons.fitness_center;
      case 'iscritti':
        return Icons.groups_outlined;
      default:
        return Icons.info_outline;
    }
  }

  // Converte la description ("Label: valore" per riga) in righe con icona.
  Widget _buildMetadata() {
    final lines = widget.description
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) {
          final idx = line.indexOf(':');
          final IconData icon;
          final String value;
          if (idx > 0) {
            icon = _iconForMeta(line.substring(0, idx).trim());
            value = line.substring(idx + 1).trim();
          } else {
            icon = Icons.info_outline;
            value = line.trim();
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: Colors.white, shadows: const [
                  Shadow(blurRadius: 4, color: Colors.black54),
                ]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(value,
                      style: const TextStyle(
                        color: Colors.white,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                      )),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // Pill che mostra i posti liberi, colorata in base alla capienza.
  Widget _capacityPill(int subscribed, int capacity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: capacityColor(subscribed, capacity),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        capacityPillLabel(subscribed, capacity),
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget renderButtonSubscribe() {
    late String buttonText;
    late Color buttonColor;
    late Color buttonTextColor;
    bool canBeClicked = false;

    if (widget.courseState == CourseState.CAN_SUBSCRIBE) {
      canBeClicked = true;
      buttonText = 'Prenotati';
      buttonColor = ghostColor;
      buttonTextColor = Colors.white;
    } else if (widget.courseState == CourseState.CLOSED) {
      return const SizedBox.shrink();
    } else if (widget.courseState == CourseState.NULL) {
      buttonText = 'Non disponibile';
      buttonColor = primaryLightColor;
      buttonTextColor = onPrimaryColor;
    } else if (widget.courseState == CourseState.LIMIT) {
      buttonText = 'Limite entrate settimanali raggiunto';
      buttonColor = primaryLightColor;
      buttonTextColor = onPrimaryColor;
    } else if (widget.courseState == CourseState.FULL) {
      buttonText = 'Corso pieno';
      buttonColor = primaryLightColor;
      buttonTextColor = onPrimaryColor;
    } else if (widget.courseState == CourseState.SUBSCRIBE_LIMIT) {
      buttonText = 'Entrate disponibili esaurite';
      buttonColor = primaryLightColor;
      buttonTextColor = onPrimaryColor;
    } else if (widget.courseState == CourseState.EXPIRED) {
      buttonText = 'Abbonamento scaduto';
      buttonColor = primaryLightColor;
      buttonTextColor = onPrimaryColor;
    } else if (widget.courseState == CourseState.SUBSCRIBED) {
      buttonText = 'Rimuovi iscrizione';
      buttonColor = dangerColor;
      buttonTextColor = Colors.white;
      canBeClicked = true;
    } else if (widget.courseState == CourseState.CAN_WAITLIST) {
      canBeClicked = true;
      buttonText = 'Lista d\'attesa';
      buttonColor = Colors.orange;
      buttonTextColor = Colors.white;
    } else if (widget.courseState == CourseState.IN_WAITLIST) {
      canBeClicked = true;
      buttonText = 'Esci dalla lista d\'attesa';
      buttonColor = dangerColor;
      buttonTextColor = Colors.white;
    } else if (widget.courseState == CourseState.WAITLIST_SPOT_AVAILABLE) {
      canBeClicked = true;
      buttonText = 'Posto disponibile! Iscriviti ora';
      buttonColor = ghostColor;
      buttonTextColor = Colors.white;
    }

    return ElevatedButton(
      onPressed: canBeClicked && !_isProcessing
          ? () async {
              if (widget.onClickAction != null) {
                setState(() => _isProcessing = true);
                try {
                  await widget.onClickAction!();
                } finally {
                  if (mounted) setState(() => _isProcessing = false);
                }
              }
            }
          : null,
      style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(buttonColor),
          minimumSize: WidgetStateProperty.all(Size.zero),
          padding: WidgetStateProperty.all(
              const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 10)),
          shape: WidgetStateProperty.all<RoundedRectangleBorder>(
              RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ))),
      child: Text(
        buttonText,
        style: TextStyle(color: buttonTextColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (widget.onClick != null) {
          widget.onClick!();
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: primaryLightColor,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Immagine come sfondo dell'intera card (usa imageKey o il default per tipologia)
            Positioned.fill(
              child: Image.asset(
                CourseImages.getCourseImage(widget.course),
                fit: BoxFit.cover,
                cacheWidth:
                    700, // evita di decodificare l'asset a piena risoluzione
                // Se l'asset non carica, ricadi sull'immagine di default del tipo;
                // se manca anche quella, mostra un fondo scuro coerente (no card "vuota").
                errorBuilder: (context, error, stackTrace) => Image.asset(
                  CourseImages.getDefaultImage(widget.course.courseType),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const ColoredBox(color: primaryDarkColor),
                ),
              ),
            ),
            // Scrim scuro per garantire la leggibilità del testo sopra l'immagine
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x8C000000),
                      Color(0x59000000),
                      Color(0xB8000000),
                    ],
                    stops: [0.0, 0.4, 1.0],
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
                  // Riga 1: Titolo + pulsanti User/Admin allineati a sinistra
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(child: renderTitle()),
                      if (widget.capacity != null &&
                          widget.subscribed != null &&
                          !widget.isAdmin)
                        renderUserButtons(),
                      if (widget.isAdmin) renderAdminButtons(),
                    ],
                  ),
                  // Riga 2: Metadati con icone (orario, trainer, tipologia)
                  if (widget.description.trim() != "") _buildMetadata(),
                  // Riga 3: Bottoni iscrizione
                  if (!widget.isAdmin)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        renderButtonSubscribe(),
                      ],
                    ),
                  // Mostra la lista cliccabile degli iscritti se richiesto
                  if (widget.showClickableSubscribers)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _hasEnrollmentMismatch()
                            ? Colors.orange.withValues(alpha: 0.92)
                            : Colors.white.withValues(alpha: 0.70),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            (widget.capacity != null && widget.capacity! > 0)
                                ? Border(
                                    left: BorderSide(
                                      color: capacityColor(
                                          widget.subscribersUsers?.length ??
                                              widget.subscribed ??
                                              0,
                                          widget.capacity!),
                                      width: 4,
                                    ),
                                  )
                                : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildClickableSubscribersList(context),
                          _buildWaitlistUsersList(context),
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

  Row renderUserButtons() {
    int waitlistCount = widget.course.waitlist.length;
    return Row(
      children: [
        if (widget.capacity != null && widget.capacity! > 0)
          _capacityPill(widget.subscribed ?? 0, widget.capacity!)
        else
          Text("${widget.subscribed}/${widget.capacity}",
              style: const TextStyle(color: Colors.white)),
        if (waitlistCount > 0)
          Text(" +$waitlistCount",
              style: const TextStyle(color: Colors.orange, fontSize: 12)),
        const SizedBox(width: 7.5),
        IconButton(
          icon: const Icon(Icons.people),
          tooltip: 'Vedi iscritti',
          onPressed: showSubscribersDialog,
          color: Colors.white,
          iconSize: 20,
        ),
      ],
    );
  }

  Widget renderAdminButtons() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Wrap(
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          if (widget.onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit, color: tertiaryColor),
              tooltip: 'Modifica corso',
              onPressed: widget.onEdit,
            ),
          if (widget.onDuplicate != null)
            IconButton(
              icon: const Icon(Icons.copy, color: tertiaryColor),
              tooltip: 'Duplica corso',
              onPressed: widget.onDuplicate,
            ),
          if (widget.onDelete != null && widget.userRole == 'Admin')
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Elimina corso',
              onPressed: showDeleteConfirmationDialog,
            ),
        ],
      ),
    );
  }
}

class AddSubscriberDialog extends StatefulWidget {
  final String courseId;
  final String courseName;
  final List<FitropeUser> existingSubscribers;
  final int capacity;

  const AddSubscriberDialog({
    super.key,
    required this.courseId,
    required this.courseName,
    required this.existingSubscribers,
    required this.capacity,
  });

  @override
  State<AddSubscriberDialog> createState() => _AddSubscriberDialogState();
}

class _AddSubscriberDialogState extends State<AddSubscriberDialog> {
  List<FitropeUser> allUsers = [];
  List<FitropeUser> filteredUsers = [];
  TextEditingController searchController = TextEditingController();
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await getUsers();
      setState(() {
        allUsers = users
            .where((user) =>
                user.isActive &&
                !widget.existingSubscribers.any((sub) => sub.uid == user.uid))
            .toList();
        filteredUsers = allUsers;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Errore nel caricamento degli utenti';
        isLoading = false;
      });
    }
  }

  void _filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredUsers = allUsers;
      } else {
        filteredUsers = allUsers.where((user) {
          final fullName = '${user.name} ${user.lastName}'.toLowerCase();
          return fullName.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _addSubscriber(String userId) async {
    try {
      await subscribeToCourse(widget.courseId, userId, force: true);
      //Navigator.pop(context, true); // Chiudi il dialog e indica che è stato aggiunto un utente
    } catch (e) {
      setState(() {
        errorMessage = 'Errore nell\'aggiunta dell\'utente al corso';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: backgroundColor,
      title: Text('Aggiungi iscritto a "${widget.courseName}"'),
      content: SizedBox(
        width: 400,
        height: 500,
        child: Column(
          children: [
            // Campo di ricerca
            TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: 'Cerca per nome o cognome',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _filterUsers,
            ),
            const SizedBox(height: 16),

            // Messaggio di errore
            if (errorMessage != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            // Lista utenti
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredUsers.isEmpty
                      ? const Center(
                          child: Text(
                            'Nessun utente disponibile',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  '${user.name.isNotEmpty ? user.name[0] : ''}${user.lastName.isNotEmpty ? user.lastName[0] : ''}',
                                ),
                              ),
                              title: Text('${user.name} ${user.lastName}'),
                              subtitle: Text(user.email),
                              trailing: IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () => _addSubscriber(user.uid),
                                tooltip: 'Aggiungi al corso',
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Chiudi',
            style: TextStyle(color: onPrimaryColor),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
}
