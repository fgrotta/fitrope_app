import 'package:fitrope_app/api/authentication/deleteUser.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

    if (entrateDisponibili != null && entrateDisponibili < 0) {
      setState(() { errorMsg = 'Le entrate disponibili non possono essere negative'; });
      return;
    }

    if (entrateSettimanali != null && entrateSettimanali < 0) {
      setState(() { errorMsg = 'Le entrate settimanali non possono essere negative'; });
      return;
    }

    try {
      final updateData = {
        'name': name,
        'lastName': lastName,
        'role': selectedRole,
        'tipologiaIscrizione': selectedTipologiaIscrizione?.toString().split('.').last,
        'entrateDisponibili': entrateDisponibili,
        'entrateSettimanali': entrateSettimanali,
        'fineIscrizione': selectedFineIscrizione != null ? Timestamp.fromDate(selectedFineIscrizione!) : null,
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .update(updateData);

      setState(() {
        isEditing = false;
        errorMsg = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utente aggiornato con successo')),
      );
    } catch (e) {
      setState(() { errorMsg = 'Errore durante l\'aggiornamento'; });
    }
  }

  void showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Elimina Utente'),
          content: Text('Sei sicuro di voler eliminare l\'utente ${widget.user.name} ${widget.user.lastName}? Questa azione non può essere annullata.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await deleteUser(widget.user.uid);
                  Navigator.pop(context);
                  Navigator.pop(context); // Torna alla lista utenti
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Utente eliminato con successo')),
                  );
                } catch (e) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Errore durante l\'eliminazione')),
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Elimina'),
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
          if (!isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: toggleEdit,
            ),
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
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Elimina', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'delete') {
                showDeleteConfirmation();
              }
            },
          ),
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

  Widget _buildInfoRow(String label, String value, TextEditingController? controller, bool isEditable, {bool isDropdown = false, bool isTipologiaDropdown = false, bool isDatePicker = false}) {
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
                        items: ['User', 'Trainer', 'Admin'].map((role) {
                          return DropdownMenuItem(
                            value: role,
                            child: Text(role),
                          );
                        }).toList(),
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