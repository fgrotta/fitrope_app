import 'package:fitrope_app/api/authentication/updateUser.dart';
import 'package:fitrope_app/api/authentication/toggleUserStatus.dart';
import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserDetailPage extends StatefulWidget {
  final FitropeUser user;

  const UserDetailPage({super.key, required this.user});

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  bool isEditing = false;
  late TextEditingController nameController;
  late TextEditingController lastNameController;
  late TextEditingController entrateDisponibiliController;
  late TextEditingController entrateSettimanaliController;
  late String selectedRole;
  late TipologiaIscrizione? selectedTipologiaIscrizione;
  late DateTime? selectedFineIscrizione;
  late bool selectedIsActive;
  late bool selectedIsAnonymous;
  String? errorMsg;
  List<Course> allCourses = [];

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.user.name);
    lastNameController = TextEditingController(text: widget.user.lastName);
    entrateDisponibiliController = TextEditingController(text: widget.user.entrateDisponibili?.toString() ?? '');
    entrateSettimanaliController = TextEditingController(text: widget.user.entrateSettimanali?.toString() ?? '');
    selectedRole = widget.user.role;
    selectedTipologiaIscrizione = widget.user.tipologiaIscrizione;
    selectedFineIscrizione = widget.user.fineIscrizione?.toDate();
    selectedIsActive = widget.user.isActive;
    selectedIsAnonymous = widget.user.isAnonymous;
    // print(widget.user.isAnonymous);
    loadCourses();
  }

  Future<void> loadCourses() async {
    try {
      final courses = await getAllCourses();
      setState(() {
        allCourses = courses;
      });
    } catch (e) {
      print('Error loading courses: $e');
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    lastNameController.dispose();
    entrateDisponibiliController.dispose();
    entrateSettimanaliController.dispose();
    super.dispose();
  }

  void toggleEdit() {
    setState(() {
      isEditing = !isEditing;
      if (!isEditing) {
        // Reset to original values if canceling edit
        nameController.text = widget.user.name;
        lastNameController.text = widget.user.lastName;
        entrateDisponibiliController.text = widget.user.entrateDisponibili?.toString() ?? '';
        entrateSettimanaliController.text = widget.user.entrateSettimanali?.toString() ?? '';
        selectedRole = widget.user.role;
        selectedTipologiaIscrizione = widget.user.tipologiaIscrizione;
        selectedFineIscrizione = widget.user.fineIscrizione?.toDate();
        selectedIsActive = widget.user.isActive;
        selectedIsAnonymous = widget.user.isAnonymous;
        errorMsg = null;
      }
    });
  }

  List<Map<String, String>> getUserCourses() {
    List<Map<String, String>> userCourses = [];
    
    var userCoursesIds = widget.user.courses.length > 10 ? widget.user.courses.sublist(widget.user.courses.length - 10) : widget.user.courses;
    for (String courseId in userCoursesIds) {
      Course? course = allCourses.where((c) => c.id == courseId).firstOrNull;
      if (course != null) {
        String courseName = course.name;
        String courseDate = DateFormat('dd/MM/yyyy').format(course.startDate.toDate());
        userCourses.add({
          'name': courseName,
          'date': courseDate,
        });
      }
    }
    
    // Ordina per data (più recenti prima) e prendi solo gli ultimi 10
    userCourses.sort((a, b) => DateFormat('dd/MM/yyyy').parse(b['date']!).compareTo(DateFormat('dd/MM/yyyy').parse(a['date']!)));
    return userCourses;
  }

  Future<void> saveChanges() async {
    final name = nameController.text.trim();
    final lastName = lastNameController.text.trim();
    final entrateDisponibili = int.tryParse(entrateDisponibiliController.text.trim());
    final entrateSettimanali = int.tryParse(entrateSettimanaliController.text.trim());
    
    if (name.isEmpty || lastName.isEmpty) {
      setState(() { errorMsg = 'Compila tutti i campi obbligatori'; });
      return;
    }
  
    if (entrateSettimanali != null && entrateSettimanali < 0) {
      setState(() { errorMsg = 'Le entrate settimanali non possono essere negative'; });
      return;
    }

    try {
      await updateUser(
        uid: widget.user.uid,
        name: name,
        lastName: lastName,
        role: selectedRole,
        tipologiaIscrizione: selectedTipologiaIscrizione,
        entrateDisponibili: entrateDisponibili,
        entrateSettimanali: entrateSettimanali,
        fineIscrizione: selectedFineIscrizione,
        isActive: selectedIsActive,
        isAnonymous: selectedIsAnonymous,
      );

      // Crea un nuovo oggetto utente con i dati aggiornati
      final updatedUser = FitropeUser(
        uid: widget.user.uid,
        email: widget.user.email,
        name: name,
        lastName: lastName,
        role: selectedRole,
        courses: widget.user.courses,
        tipologiaIscrizione: selectedTipologiaIscrizione,
        entrateDisponibili: entrateDisponibili,
        entrateSettimanali: entrateSettimanali,
        fineIscrizione: selectedFineIscrizione != null 
            ? Timestamp.fromDate(DateTime(selectedFineIscrizione!.year, selectedFineIscrizione!.month, selectedFineIscrizione!.day, 23, 59))
            : null,
        isActive: selectedIsActive,
        isAnonymous: selectedIsAnonymous,
        createdAt: widget.user.createdAt,
      );

      setState(() {
        isEditing = false;
        errorMsg = null;
      });

      // Notifica la pagina precedente del cambiamento
      Navigator.pop(context, updatedUser);

      SnackBarUtils.showSuccessSnackBar(
        context,
        'Utente aggiornato con successo',
      );
    } catch (e) {
      setState(() { errorMsg = 'Errore durante l\'aggiornamento'; });
    }
  }

  void showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Conferma Logout'),
          content: const Text('Sei sicuro di voler effettuare il logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await signOut();
                  Navigator.pop(context); // Chiudi la modale
                  logoutRedirect(context); // Reindirizza al login
                } catch (e) {
                  Navigator.pop(context);
                  SnackBarUtils.showErrorSnackBar(
                    context,
                    'Errore durante il logout',
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  void showDeleteAccountConfirmation() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancellazione Account'),
          content: const Text(
            'Sei sicuro di voler Disattivare il tuo account?\n\n'
            'I tuoi dati verranno mantenuti ma non sarai più in grado di utilizzare l\'applicazione.\n\n'
            'Se cambi idea, contatta l\'amministratore per riattivare il tuo account.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  // Disattiva l'account dell'utente
                  await toggleUserStatus(widget.user.uid, false);
                  Navigator.pop(context); // Chiudi la modale
                  
                  // Mostra messaggio di conferma
                  SnackBarUtils.showSuccessSnackBar(
                    context,
                    'Account disattivato con successo. Sei stato sloggato.',
                  );
                  
                  // Effettua il logout immediatamente
                  await signOut();
                  // Verifica se il context è ancora valido prima di navigare
                  if (context.mounted) {
                    logoutRedirect(context);
                  }
                } catch (e) {
                  Navigator.pop(context);
                  SnackBarUtils.showErrorSnackBar(
                    context,
                    'Errore durante la cancellazione dell\'account',
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancella Account'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: Text('Dettagli Utente'),
        actions: [
          if (!isEditing) ...[            
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              onPressed: showDeleteAccountConfirmation,
              tooltip: 'Cancella Account',
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: toggleEdit,
            ),
          ],
          if (isEditing) ...[
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: saveChanges,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: toggleEdit,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con avatar e nome
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: primaryColor,
                    child: Text(
                      '${widget.user.name.isNotEmpty ? widget.user.name[0] : ''}${widget.user.lastName.isNotEmpty ? widget.user.lastName[0] : ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${widget.user.name} ${widget.user.lastName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.user.role,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (!widget.user.isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.block, color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Disattivato',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Sezione informazioni personali
            _buildSection(
              'Informazioni Personali',
              [
                _buildInfoRow('Nome', widget.user.name, nameController, isEditing),
                _buildInfoRow('Cognome', widget.user.lastName, lastNameController, isEditing),
                _buildInfoRow('Email', widget.user.email, null, false),
                _buildInfoRow('Ruolo', widget.user.role, null, isEditing, isDropdown: true),
                _buildInfoRow('Stato', widget.user.isActive ? 'Attivo' : 'Disattivato', null, isEditing, isStatusDropdown: true),
                _buildInfoRow('Anonimo', widget.user.isAnonymous ? 'Si' : 'No', null, isEditing, isAnonymousDropdown: true),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Sezione piano di iscrizione
            _buildSection(
              'Piano di Iscrizione',
              [
                _buildInfoRow('Tipologia', _getTipologiaLabel(widget.user.tipologiaIscrizione), null, isEditing, isTipologiaDropdown: true),
                _buildInfoRow('Entrate Disponibili', widget.user.entrateDisponibili?.toString() ?? '0', entrateDisponibiliController, isEditing),
                _buildInfoRow('Entrate Settimanali', widget.user.entrateSettimanali?.toString() ?? '0', entrateSettimanaliController, isEditing),
                _buildInfoRow('Fine Iscrizione', widget.user.fineIscrizione != null ? DateFormat('dd/MM/yyyy').format(widget.user.fineIscrizione!.toDate()) : 'Non impostata', null, isEditing, isDatePicker: true),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Sezione informazioni account
            _buildSection(
              'Informazioni Account',
              [
                _buildInfoRow('Data Registrazione', DateFormat('dd/MM/yyyy HH:mm').format(widget.user.createdAt), null, false),
                _buildInfoRow('Corsi Iscritti', '${widget.user.courses.length}', null, false),
              ],
            ),
            
            if (widget.user.courses.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSection(
                'Ultimi 10 iscrizioni',
                getUserCourses().map((courseInfo) => 
                  _buildInfoRow(courseInfo['name']!, courseInfo['date']!, null, false)
                ).toList(),
              ),
            ],
            //TODO aggiungere corsi fatti nel caso sia Trainer
            if (errorMsg != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Text(
                    errorMsg!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            
            // Pulsante Logout
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: showLogoutConfirmation,
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, TextEditingController? controller, bool isEditable, {bool isDropdown = false, bool isTipologiaDropdown = false, bool isDatePicker = false, bool isStatusDropdown = false, bool isAnonymousDropdown = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: isEditable && controller != null
                ? TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  )
                : isEditable && isDropdown
                    ? DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'User',
                            child: Text('User'),
                          ),
                          // Solo gli admin possono assegnare il ruolo Trainer
                          if (store.state.user?.role == 'Admin')
                            DropdownMenuItem(
                              value: 'Trainer',
                              child: Text('Trainer'),
                            ),
                          DropdownMenuItem(
                            value: 'Admin',
                            child: Text('Admin'),
                          ),
                        ],
                        onChanged: (newValue) {
                          setState(() {
                            selectedRole = newValue!;
                          });
                        },
                      )
                    : isEditable && isTipologiaDropdown
                        ? DropdownButtonFormField<String>(
                            value: selectedTipologiaIscrizione?.toString().split('.').last,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: [
                              DropdownMenuItem(value: null, child: Text('Nessuna')),
                              ...TipologiaIscrizione.values.map((tipologia) {
                                return DropdownMenuItem(
                                  value: tipologia.toString().split('.').last,
                                  child: Text(_getTipologiaLabel(tipologia)),
                                );
                              }),
                            ],
                            onChanged: (newValue) {
                              setState(() {
                                selectedTipologiaIscrizione = newValue != null 
                                    ? TipologiaIscrizione.values.where((e) => e.toString().split('.').last == newValue).firstOrNull
                                    : null;
                              });
                            },
                          )
                                                    : isEditable && isDatePicker
                            ? InkWell(
                                onTap: () async {
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: selectedFineIscrizione ?? DateTime.now(),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      selectedFineIscrizione = picked;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        selectedFineIscrizione != null 
                                            ? DateFormat('dd/MM/yyyy').format(selectedFineIscrizione!)
                                            : 'Seleziona data',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      const Icon(Icons.calendar_today),
                                    ],
                                  ),
                                ),
                              )
                            : isEditable && isStatusDropdown
                            ? DropdownButtonFormField<bool>(
                                value: selectedIsActive,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: true,
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle, color: Colors.green),
                                        SizedBox(width: 8),
                                        Text('Attivo'),
                                      ],
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: false,
                                    child: Row(
                                      children: [
                                        Icon(Icons.block, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Disattivato'),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (newValue) {
                                  setState(() {
                                    selectedIsActive = newValue!;
                                  });
                                },
                              )
                            : isEditable && isAnonymousDropdown
                            ? DropdownButtonFormField<bool>(
                                value: selectedIsAnonymous,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: false,
                                    child: Row(
                                      children: [
                                        Icon(Icons.person, color: Colors.green),
                                        SizedBox(width: 8),
                                        Text('No'),
                                      ],
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: true,
                                    child: Row(
                                      children: [
                                        Icon(Icons.visibility_off, color: Colors.grey),
                                        SizedBox(width: 8),
                                        Text('Sì'),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (newValue) {
                                  setState(() {
                                    selectedIsAnonymous = newValue!;
                                  });
                                },
                              )
                            : Text(
                                value,
                                style: const TextStyle(
                                  fontSize: 16,
                                ),
                              ),
          ),
        ],
      ),
    );
  }

  String _getTipologiaLabel(TipologiaIscrizione? tipologia) {
    if (tipologia == null) return 'Nessuna';
    switch (tipologia) {
      case TipologiaIscrizione.PACCHETTO_ENTRATE:
        return 'Pacchetto Entrate';
      case TipologiaIscrizione.ABBONAMENTO_MENSILE:
        return 'Abbonamento Mensile';
      case TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE:
        return 'Abbonamento Trimestrale';
    }
  }
}