import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/courses/subscribeToCourse.dart';
import 'package:fitrope_app/api/courses/deleteCourse.dart';
import 'package:fitrope_app/api/courses/updateCourseSubscribedCount.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/types/course.dart';

enum CourseState {
  NULL,
  EXPIRED,
  CAN_SUBSCRIBE,
  FULL,
  SUBSCRIBED
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
  final List<FitropeUser>? subscribersUsers; // Lista degli utenti iscritti per la versione cliccabile
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback onRefresh; // Callback per aggiornare la lista
  final bool isAdmin;
  final String? userRole; // Ruolo dell'utente corrente
  final bool showClickableSubscribers; // Se true, mostra la lista cliccabile invece del dialog

  const CourseCard({
    required this.courseId,
    required this.course,
    super.key, 
    required this.title,
    this.courseState=CourseState.NULL,
    this.titleStyle,
    this.description="",
    this.descriptionStyle,
    this.onClick,
    this.onClickAction,
    this.capacity,
    this.subscribed,
    this.subscribersNames,
    this.subscribersUsers,
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
  void showSubscribersDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        title: const Text('Iscritti al corso'),
        content: widget.subscribersNames == null || widget.subscribersNames!.isEmpty
          ? const Text('Nessun iscritto')
          : SizedBox(
              width: 300,
              child: ListView(
                shrinkWrap: true,
                children: widget.subscribersNames!.map((name) => ListTile(title: Text(name))).toList(),
              ),
            ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi', style: TextStyle(color: onPrimaryColor),),
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
        content: Text('Sei sicuro di voler eliminare il corso "${widget.title}"?\n\nQuesta azione eliminerà anche tutte le iscrizioni al corso.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla', style: TextStyle(color: onPrimaryColor),),
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
      widget.onRefresh!();
    }
  }

  void _showRemoveUserConfirmationDialog(BuildContext context, FitropeUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        title: const Text('Rimuovi Iscrizione'),
        content: Text(
          'Sei sicuro di voler rimuovere ${user.name} ${user.lastName} dal corso "${widget.title}"?\n\n'
          'L\'utente riceverà il rimborso del credito se ha un pacchetto entrate.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla', style: TextStyle(color: onPrimaryColor),),
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
        widget.onRefresh!();
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
              child: const Text('Annulla', style: TextStyle(color: onPrimaryColor)),
            ),
            ElevatedButton(
              onPressed: () => _correctSubscribedCount(context, actualCount),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Correggi', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // Corregge il conteggio degli iscritti nel database
  Future<void> _correctSubscribedCount(BuildContext context, int newCount) async {
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Iscritti (${widget.subscribersUsers!.length}/${widget.capacity}):', style: const TextStyle(color: surfaceVariantColor, fontWeight: FontWeight.bold)),
            // Icona + per aggiungere iscritti (solo per Admin)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                
                if (widget.isAdmin)
                  IconButton(
                    icon: const Icon(Icons.add, color: surfaceVariantColor, size: 20),
                    onPressed: () => _showAddSubscriberDialog(context),
                    tooltip: 'Aggiungi iscritto',
                  ),
                if (_hasEnrollmentMismatch())
                  IconButton(
                  icon: const Icon(Icons.sync_problem, color: Colors.red, size: 20),
                  onPressed: () => _showCorrectCountDialog(context),
                  tooltip: 'Correggi conteggio iscritti',
                ),
          ])],
        ),
        const SizedBox(height: 4),
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
                          color: surfaceVariantColor,
                          decoration: TextDecoration.none, 
                        ),
                      ),
                    ),
                  ),
                ),
                // Pulsante di rimozione per admin/trainer
                if (widget.isAdmin || widget.userRole == 'Trainer')
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 16),
                    onPressed: () => _showRemoveUserConfirmationDialog(context, user),
                    tooltip: 'Rimuovi iscrizione',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          );
        }).toList(),
      ],
    );
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
    if(widget.titleStyle != null) {
      return Text("Corso: " + widget.title, overflow: TextOverflow.visible, style: widget.titleStyle,);
    }

    return Text("Corso: " + widget.title, style: const TextStyle(color: Colors.white, ),);
  }

  Widget renderButtonSubscribe() {
    late String buttonText;
    late Color buttonColor;
    late Color buttonTextColor;
    bool canBeClicked = false;

    if(widget.courseState == CourseState.CAN_SUBSCRIBE) {
      canBeClicked = true;
      buttonText = 'Prenotati';
      buttonColor = ghostColor;
      buttonTextColor = Colors.white;
    }
    else if(
      widget.courseState == CourseState.FULL ||
      widget.courseState == CourseState.EXPIRED
    ) {
      buttonText = 'Non disponibile';
      buttonColor = primaryLightColor;
      buttonTextColor = const Color.fromARGB(86, 255, 255, 255);
    }
    else if(widget.courseState == CourseState.SUBSCRIBED) {
      buttonText = 'Rimuovi iscrizione';
      buttonColor = dangerColor;
      buttonTextColor = Colors.white;
      canBeClicked = true;
    }

    return ElevatedButton(
      onPressed: canBeClicked ? () {
        if(widget.onClickAction != null) {
          widget.onClickAction!();
        }
      } : null,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(buttonColor),
        minimumSize: WidgetStateProperty.all(Size.zero),
        padding: WidgetStateProperty.all(const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 10)),
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          )
        )
      ), 
      child: Text(buttonText, style: TextStyle(color: buttonTextColor),),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if(widget.onClick != null) {
          widget.onClick!();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          color: primaryLightColor,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Riga 1: Titolo + pulsanti User/Admin allineati a sinistra
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  renderTitle(),
                  if(widget.capacity != null && widget.subscribed != null && !widget.isAdmin) renderUserButtons(),
                  if(widget.isAdmin) renderAdminButtons(),
                ],
              ),
            // Riga 2: Descrizione
            if(widget.description != "") Text(widget.description, style: const TextStyle(color: Colors.white, ),),
            // Riga 3: Bottoni iscrizione
            if(widget.courseState != CourseState.NULL && !widget.isAdmin)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  renderButtonSubscribe(),
                ],
              ),
            // Mostra la lista cliccabile degli iscritti se richiesto
            if(widget.showClickableSubscribers)
              Container(
                margin: const EdgeInsets.only(top: 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _hasEnrollmentMismatch() ? Colors.orange : primaryDarkColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildClickableSubscribersList(context),
              ),
          ],
        ),
      ),
    );
  }
Row renderUserButtons() {
return 
Row(
                      children: [
                        Text("${widget.subscribed}/${widget.capacity}", style: const TextStyle(color: onPrimaryColor),),
                        const SizedBox(width: 7.5,),
                        IconButton(
                            icon: const Icon(Icons.people),
                            tooltip: 'Vedi iscritti',
                            onPressed: showSubscribersDialog,
                            color: onPrimaryColor, 
                            iconSize: 20,
                          ),
                        
                      ],
                    );
}
     

  Widget renderAdminButtons() {
    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        if(widget.onEdit != null)
          IconButton(
            icon: const Icon(Icons.edit, color: onPrimaryColor),
            tooltip: 'Modifica corso',
            onPressed: widget.onEdit,
          ),
        if(widget.onDuplicate != null)
          IconButton(
            icon: const Icon(Icons.copy, color: tertiaryColor),
            tooltip: 'Duplica corso',
            onPressed: widget.onDuplicate,
          ),
        if(widget.onDelete != null && widget.userRole == 'Admin')
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            tooltip: 'Elimina corso',
            onPressed: showDeleteConfirmationDialog,
          ),
      ],
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
        allUsers = users.where((user) => 
          user.isActive && 
          !widget.existingSubscribers.any((sub) => sub.uid == user.uid)
        ).toList();
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
          child: const Text('Chiudi', style: TextStyle(color: onPrimaryColor),),
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