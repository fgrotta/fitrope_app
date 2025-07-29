import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/courses/subscribeToCourse.dart';
import 'package:flutter/material.dart';

enum CourseState {
  NULL,
  EXPIRED,
  CAN_SUBSCRIBE,
  FULL,
  SUBSCRIBED
}

class CourseCard extends StatefulWidget {
  final String courseId;
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
  final VoidCallback? onRefresh; // Callback per aggiornare la lista
  final bool isAdmin;
  final bool showClickableSubscribers; // Se true, mostra la lista cliccabile invece del dialog

  const CourseCard({
    required this.courseId,
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
    this.onRefresh,
    this.isAdmin = false,
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
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  void showDeleteConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina Corso'),
        content: Text('Sei sicuro di voler eliminare il corso "${widget.title}"?\n\nQuesta azione eliminerà anche tutte le iscrizioni al corso.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
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
    if (result == true && widget.onRefresh != null) {
      widget.onRefresh!();
    }
  }

  Widget _buildClickableSubscribersList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Iscritti (${widget.subscribersUsers!.length}/${widget.capacity}):', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            // Icona + per aggiungere iscritti (solo per Admin)
            if (widget.isAdmin)
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white, size: 20),
                onPressed: () => _showAddSubscriberDialog(context),
                tooltip: 'Aggiungi iscritto',
              ),
          ],
        ),
        const SizedBox(height: 4),
        ...widget.subscribersUsers!.map((user) {
          final displayName = '${user.name} ${user.lastName}';
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: GestureDetector(
              onTap: () => _showUserDetails(context, user),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  '• $displayName',
                  style: const TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.none, 
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget renderTitle() {
    if(widget.titleStyle != null) {
      return Text("Corso: " + widget.title, overflow: TextOverflow.visible, style: widget.titleStyle,);
    }

    return Text("Corso: " + widget.title, style: const TextStyle(color: Colors.white, ),);
  }

  Widget renderButton() {
    late String buttonText;
    late Color buttonColor;
    late Color buttonTextColor;
    bool canBeClicked = false;

    if(widget.courseState == CourseState.CAN_SUBSCRIBE) {
      canBeClicked = true;
      buttonText = 'Prenotati';
      buttonColor = actionColor;
      buttonTextColor = Colors.white;
    }
    else if(
      widget.courseState == CourseState.FULL ||
      widget.courseState == CourseState.EXPIRED
    ) {
      buttonText = 'Non disponibile';
      buttonColor = ghostColor;
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
          color: primaryColor,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        renderTitle(),
                      ],
                    ),
                    if(widget.description != "") const SizedBox(height: 10,),
                    if(widget.description != "") Text(widget.description, style: const TextStyle(color: Colors.white, ),)
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if(widget.capacity != null && widget.subscribed != null && !widget.isAdmin) Row(
                      children: [
                        Text("${widget.subscribed}/${widget.capacity}", style: const TextStyle(color: ghostColor),),
                        const SizedBox(width: 7.5,),
                        IconButton(
                            icon: const Icon(Icons.people),
                            tooltip: 'Vedi iscritti',
                            onPressed: showSubscribersDialog,
                            color: ghostColor, 
                            iconSize: 20,
                          ),
                        
                      ],
                    ),
                    const SizedBox(height: 10,),
                    if(widget.courseState != CourseState.NULL && !widget.isAdmin) renderButton(),
                    if(widget.isAdmin)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if(widget.onEdit != null)
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.orange),
                              tooltip: 'Modifica corso',
                              onPressed: widget.onEdit,
                            ),
                          if(widget.onDuplicate != null)
                            IconButton(
                              icon: const Icon(Icons.copy, color: Colors.blue),
                              tooltip: 'Duplica corso',
                              onPressed: widget.onDuplicate,
                            ),
                          if(widget.onDelete != null)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Elimina corso',
                              onPressed: showDeleteConfirmationDialog,
                            ),
                        ],
                      ),
                  ],
                )
              ],
            ),
            // Mostra la lista cliccabile degli iscritti se richiesto
            if(widget.showClickableSubscribers)
              Container(
                margin: const EdgeInsets.only(top: 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildClickableSubscribersList(context),
              ),
          ],
        ),
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
          child: const Text('Chiudi'),
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