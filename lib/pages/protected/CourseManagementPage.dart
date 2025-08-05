import 'package:fitrope_app/api/courses/createCourse.dart';
import 'package:fitrope_app/api/courses/updateCourse.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/components/loader.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CourseManagementPage extends StatefulWidget {
  final Course? courseToEdit;
  final Course? courseToDuplicate;
  final String mode; // 'create', 'edit', 'duplicate'

  const CourseManagementPage({
    super.key,
    this.courseToEdit,
    this.courseToDuplicate,
    required this.mode,
  });

  @override
  State<CourseManagementPage> createState() => _CourseManagementPageState();
}

class _CourseManagementPageState extends State<CourseManagementPage> {
  final nameController = TextEditingController();
  final durationController = TextEditingController();
  final capacityController = TextEditingController();
  
  late FitropeUser user;
  List<FitropeUser> trainers = [];
  DateTime? startDate;
  String? selectedTrainerId;
  String? errorMsg;
  bool isLoading = false;
  
  final defaultTimeOfDay = const TimeOfDay(hour: 19, minute: 0);

  @override
  void initState() {
    super.initState();
    user = store.state.user!;
    
    // Controlla se l'utente ha i permessi per accedere a questa pagina
    if (user.role != 'Admin' && user.role != 'Trainer') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pop(context);
        SnackBarUtils.showErrorSnackBar(
          context,
          'Non hai i permessi per accedere a questa pagina',
        );
      });
      return;
    }
    
    // Controlla se il Trainer può modificare questo corso specifico
    if (user.role == 'Trainer' && widget.mode == 'edit' && widget.courseToEdit != null) {
      final course = widget.courseToEdit!;
      if (course.trainerId != null && course.trainerId != user.uid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pop(context);
          SnackBarUtils.showErrorSnackBar(
            context,
            'Non puoi modificare un corso assegnato a un altro trainer',
          );
        });
        return;
      }
    }
    
    _initializeData();
  }

  void _initializeData() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Carica i trainer
      final trainersResponse = await getTrainers();
      setState(() {
        trainers = trainersResponse;
      });

      // Inizializza i dati del corso
      _initializeCourseData();
    } catch (e) {
      SnackBarUtils.showErrorSnackBar(context, 'Errore nel caricamento dei dati');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _initializeCourseData() {
    // Inizializza startDate
    startDate = widget.courseToEdit?.startDate.toDate() ?? 
                widget.courseToDuplicate?.startDate.toDate() ?? 
                DateTime.now();

    // Per la creazione di nuovi corsi, non permettere date nel passato
    if (widget.mode == 'create' && startDate!.isBefore(DateTime.now())) {
      DateTime now = DateTime.now();
      startDate = DateTime(now.year, now.month, now.day, defaultTimeOfDay.hour, defaultTimeOfDay.minute);
    }
    // Per la modifica, permettere date future anche se il corso originale era nel passato

    // Inizializza i controller
    nameController.text = widget.courseToEdit?.name ?? 
                         widget.courseToDuplicate?.name ?? '';

    if (widget.courseToEdit != null) {
      // Per l'editing, non mostrare la durata
      durationController.text = '';
    } else {
      // Per creazione e duplicazione
      final course = widget.courseToEdit ?? widget.courseToDuplicate;
      if (course != null) {
        final duration = course.endDate.toDate().difference(course.startDate.toDate()).inHours;
        durationController.text = duration.toString();
      } else {
        durationController.text = '1';
      }
    }

    capacityController.text = widget.courseToEdit?.capacity.toString() ?? 
                             widget.courseToDuplicate?.capacity.toString() ?? '6';

    // Inizializza il trainer
    selectedTrainerId = widget.courseToEdit?.trainerId ?? 
                       widget.courseToDuplicate?.trainerId;
    
    // Se è un Trainer che sta creando un nuovo corso, assegna automaticamente se stesso
    if (user.role == 'Trainer' && widget.mode == 'create' && selectedTrainerId == null) {
      selectedTrainerId = user.uid;
    }
  }

  String _getPageTitle() {
    switch (widget.mode) {
      case 'create':
        return 'Crea Nuovo Corso';
      case 'edit':
        return 'Modifica Corso';
      case 'duplicate':
        return 'Duplica Corso';
      default:
        return 'Gestione Corso';
    }
  }

  String _getActionButtonText() {
    switch (widget.mode) {
      case 'create':
        return 'Crea';
      case 'edit':
        return 'Salva';
      case 'duplicate':
        return 'Duplica';
      default:
        return 'Conferma';
    }
  }

  Future<void> _selectDate() async {
    // Per la modifica, permettere di selezionare date future anche se il corso originale era nel passato
    DateTime firstDate = DateTime.now();
    if (widget.mode == 'edit' && widget.courseToEdit != null) {
      // Se stiamo modificando un corso, permettere di spostarlo nel futuro
      firstDate = DateTime.now().subtract(const Duration(days: 1));
    }
    
    final picked = await showDatePicker(
      context: context,
      initialEntryMode: DatePickerEntryMode.calendar,
      initialDate: startDate ?? DateTime.now(),
      firstDate: firstDate,
      lastDate: DateTime(DateTime.now().year + 1),
    );
    
    if (picked != null) {
      setState(() {
        startDate = DateTime(
          picked.year, 
          picked.month, 
          picked.day, 
          startDate?.hour ?? defaultTimeOfDay.hour, 
          startDate?.minute ?? defaultTimeOfDay.minute
        );
      });
    }
  }

  Future<void> _selectTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: startDate != null ? TimeOfDay.fromDateTime(startDate!) : defaultTimeOfDay,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    
    if (pickedTime != null) {
      setState(() {
        startDate = DateTime(
          startDate?.year ?? DateTime.now().year, 
          startDate?.month ?? DateTime.now().month, 
          startDate?.day ?? DateTime.now().day, 
          pickedTime.hour, 
          pickedTime.minute
        );
      });
    }
  }

  bool _validateForm() {
    final name = nameController.text.trim();
    final duration = double.tryParse(durationController.text.trim()) ?? 0;
    final capacity = int.tryParse(capacityController.text.trim()) ?? 0;
    
    if (name.isEmpty) {
      setState(() { errorMsg = 'Il nome del corso è obbligatorio'; });
      return false;
    }
    
    if (startDate == null) {
      setState(() { errorMsg = 'Seleziona una data e un orario'; });
      return false;
    }
    
    // Per la creazione di nuovi corsi, non permettere date nel passato
    if (widget.mode == 'create' && startDate!.isBefore(DateTime.now())) {
      setState(() { errorMsg = 'Non puoi creare un corso nel passato'; });
      return false;
    }
    
    // Per la modifica, permettere di spostare corsi nel futuro
    // Non impedire la modifica di corsi nel passato, permettere di spostarli nel futuro
    
    if (capacity <= 0) {
      setState(() { errorMsg = 'Il numero di partecipanti deve essere maggiore di 0'; });
      return false;
    }
    
    if (widget.mode != 'edit' && duration <= 0) {
      setState(() { errorMsg = 'La durata deve essere maggiore di 0'; });
      return false;
    }
    
    setState(() { errorMsg = null; });
    return true;
  }

  Future<void> _saveCourse() async {
    if (!_validateForm()) return;

    setState(() {
      isLoading = true;
    });

    try {
      final name = nameController.text.trim();
      final duration = double.tryParse(durationController.text.trim()) ?? 1;
      final capacity = int.tryParse(capacityController.text.trim()) ?? 6;
      final endDate = startDate!.add(Duration(hours: duration.toInt()));

      if (widget.mode == 'edit' && widget.courseToEdit != null) {
        // Modifica corso esistente
        // I Trainer non possono cambiare il trainer assegnato
        final trainerId = user.role == 'Trainer' ? widget.courseToEdit!.trainerId : selectedTrainerId;
        
        final updatedCourse = Course(
          uid: widget.courseToEdit!.uid,
          id: widget.courseToEdit!.uid,
          name: name,
          startDate: Timestamp.fromDate(startDate!),
          endDate: Timestamp.fromDate(endDate),
          capacity: capacity,
          subscribed: widget.courseToEdit!.subscribed,
          trainerId: trainerId,
        );
        
        await updateCourse(updatedCourse);
        SnackBarUtils.showSuccessSnackBar(context, 'Corso modificato con successo');
      } else {
        // Crea nuovo corso (creazione o duplicazione)
        // I Trainer vengono automaticamente assegnati ai corsi che creano
        final trainerId = user.role == 'Trainer' ? user.uid : selectedTrainerId;
        
        final newCourse = Course(
          uid: '',
          id: '',
          name: name,
          startDate: Timestamp.fromDate(startDate!),
          endDate: Timestamp.fromDate(endDate),
          capacity: capacity,
          subscribed: 0,
          trainerId: trainerId,
        );
        
        await createCourse(newCourse);
        
        final isDuplication = widget.mode == 'duplicate';
        SnackBarUtils.showSuccessSnackBar(
          context,
          isDuplication ? 'Corso duplicato con successo' : 'Corso creato con successo',
        );
      }

      // Torna alla pagina precedente
      Navigator.pop(context, true); // true indica che è stato fatto un salvataggio
    } catch (e) {
      final action = widget.mode == 'edit' ? 'modifica' : 
                    widget.mode == 'duplicate' ? 'duplicazione' : 'creazione';
      SnackBarUtils.showErrorSnackBar(
        context,
        'Errore durante la $action del corso',
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(_getPageTitle()),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Campo Nome
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome corso',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),

                // Selezione Data
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Data e Ora',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Data:'),
                                  const SizedBox(height: 4),
                                  Text(
                                    startDate != null 
                                      ? DateFormat('dd/MM/yyyy').format(startDate!)
                                      : 'Non selezionata',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _selectDate,
                              icon: const Icon(Icons.calendar_today),
                              label: const Text('Seleziona Data'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Ora:'),
                                  const SizedBox(height: 4),
                                  Text(
                                    startDate != null 
                                      ? DateFormat('HH:mm').format(startDate!)
                                      : 'Non selezionata',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _selectTime,
                              icon: const Icon(Icons.access_time),
                              label: const Text('Seleziona Ora'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Campo Durata (solo per creazione e duplicazione)
                if (widget.mode != 'edit')
                  TextField(
                    controller: durationController,
                    decoration: const InputDecoration(
                      labelText: 'Durata (ore)',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                if (widget.mode != 'edit') const SizedBox(height: 20),

                // Campo Capacità
                TextField(
                  controller: capacityController,
                  decoration: const InputDecoration(
                    labelText: 'Numero massimo partecipanti',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),

                // Selezione Trainer (solo per admin)
                if (user.role == 'Admin') ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Trainer',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: selectedTrainerId,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            hint: const Text('Seleziona un trainer'),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('Nessun trainer'),
                              ),
                              ...trainers.map((trainer) {
                                return DropdownMenuItem<String>(
                                  value: trainer.uid,
                                  child: Text('${trainer.name} ${trainer.lastName}'),
                                );
                              }).toList(),
                            ],
                            onChanged: (newValue) {
                              setState(() {
                                selectedTrainerId = newValue;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Messaggio di errore
                if (errorMsg != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Text(
                      errorMsg!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),

                const SizedBox(height: 30),

                // Pulsanti
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Annulla'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _saveCourse,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(_getActionButtonText()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isLoading) const Loader(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    durationController.dispose();
    capacityController.dispose();
    super.dispose();
  }
} 