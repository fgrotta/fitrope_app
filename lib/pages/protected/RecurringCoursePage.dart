import 'package:fitrope_app/api/courses/createCourse.dart';
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

class RecurringCoursePage extends StatefulWidget {
  const RecurringCoursePage({super.key});

  @override
  State<RecurringCoursePage> createState() => _RecurringCoursePageState();
}

class _RecurringCoursePageState extends State<RecurringCoursePage> {
  final nameController = TextEditingController();
  final durationController = TextEditingController();
  final capacityController = TextEditingController();
  
  late FitropeUser user;
  List<FitropeUser> trainers = [];
  DateTime? startDate;
  DateTime? endDate;
  String? selectedTrainerId;
  String? errorMsg;
  bool isLoading = false;
  
  // Variabili per corsi ricorrenti
  Map<int, bool> selectedDays = {
    1: false, // Lunedì
    2: false, // Martedì
    3: false, // Mercoledì
    4: false, // Giovedì
    5: false, // Venerdì
    6: false, // Sabato
    7: false, // Domenica
  };
  
  final defaultTimeOfDay = const TimeOfDay(hour: 19, minute: 0);
  
  // Nomi dei giorni in italiano
  final Map<int, String> dayNames = {
    1: 'Lunedì',
    2: 'Martedì',
    3: 'Mercoledì',
    4: 'Giovedì',
    5: 'Venerdì',
    6: 'Sabato',
    7: 'Domenica',
  };



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

      // Inizializza i dati
      _initializeCourseData();
    } catch (e) {
      SnackBarUtils.showErrorSnackBar(context, 'Errore nel caricamento dei dati');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }
String _getDayName(DateTime date) {
  switch (date.weekday) {
    case 1: return 'Lunedì';
    case 2: return 'Martedì';
    case 3: return 'Mercoledì';
    case 4: return 'Giovedì';
    case 5: return 'Venerdì';
    case 6: return 'Sabato';
    case 7: return 'Domenica';
    default: return '';
  }
}

  void _initializeCourseData() {
    // Inizializza startDate a oggi
    startDate = DateTime.now();
    
    // Inizializza endDate a 1 mese da oggi
    endDate = DateTime.now().add(const Duration(days: 30));
    
    // Inizializza i controller
    nameController.text = '';
    durationController.text = '1';
    capacityController.text = '6';
    
    // Inizializza il trainer
    selectedTrainerId = null;
    
    // Se è un Trainer, assegna automaticamente se stesso
    if (user.role == 'Trainer') {
      selectedTrainerId = user.uid;
    }
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialEntryMode: DatePickerEntryMode.calendar,
      initialDate: startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 150)), // 5 mesi
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

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialEntryMode: DatePickerEntryMode.calendar,
      initialDate: endDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: startDate ?? DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 150)), // 5 mesi
    );
    
    if (picked != null) {
      setState(() {
        endDate = DateTime(picked.year, picked.month, picked.day);
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

  void _toggleDay(int day) {
    setState(() {
      selectedDays[day] = !selectedDays[day]!;
    });
  }

  List<DateTime> _calculateCourseDates() {
    if (startDate == null || endDate == null) return [];
    
    List<DateTime> dates = [];
    DateTime currentDate = DateTime(
      startDate!.year,
      startDate!.month,
      startDate!.day,
    );
    
    while (currentDate.isBefore(endDate!) || currentDate.isAtSameMomentAs(endDate!)) {
      int weekday = currentDate.weekday;
      if (selectedDays[weekday] == true) {
        dates.add(DateTime(
          currentDate.year,
          currentDate.month,
          currentDate.day,
          startDate!.hour,
          startDate!.minute,
        ));
      }
      currentDate = currentDate.add(const Duration(days: 1));
    }
    
    return dates;
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
      setState(() { errorMsg = 'Seleziona una data di inizio'; });
      return false;
    }
    
    if (endDate == null) {
      setState(() { errorMsg = 'Seleziona una data di fine'; });
      return false;
    }
    
    if (startDate!.isAfter(endDate!)) {
      setState(() { errorMsg = 'La data di inizio deve essere precedente alla data di fine'; });
      return false;
    }
    
    // Verifica che non sia oltre 5 mesi
    final maxDate = DateTime.now().add(const Duration(days: 150));
    if (endDate!.isAfter(maxDate)) {
      setState(() { errorMsg = 'La data di fine non può essere oltre 5 mesi da oggi'; });
      return false;
    }
    
    // Verifica che almeno un giorno sia selezionato
    bool hasSelectedDay = selectedDays.values.any((selected) => selected);
    if (!hasSelectedDay) {
      setState(() { errorMsg = 'Seleziona almeno un giorno della settimana'; });
      return false;
    }
    
    if (capacity <= 0) {
      setState(() { errorMsg = 'Il numero di partecipanti deve essere maggiore di 0'; });
      return false;
    }
    
    if (duration <= 0) {
      setState(() { errorMsg = 'La durata deve essere maggiore di 0'; });
      return false;
    }
    
    setState(() { errorMsg = null; });
    return true;
  }

  Future<void> _createRecurringCourses() async {
    if (!_validateForm()) return;

    setState(() {
      isLoading = true;
    });

    try {
      final name = nameController.text.trim();
      final duration = double.tryParse(durationController.text.trim()) ?? 1;
      final capacity = int.tryParse(capacityController.text.trim()) ?? 6;
      
      // Calcola le date dei corsi
      final courseDates = _calculateCourseDates();
      
      if (courseDates.isEmpty) {
        setState(() { errorMsg = 'Nessuna data valida trovata per i giorni selezionati'; });
        return;
      }
      
      // I Trainer vengono automaticamente assegnati ai corsi che creano
      final trainerId = user.role == 'Trainer' ? user.uid : selectedTrainerId;
      
      int createdCount = 0;
      
      // Crea un corso per ogni data
      for (DateTime courseDate in courseDates) {
        final endDate = courseDate.add(Duration(hours: duration.toInt()));
        
        final newCourse = Course(
          uid: '',
          id: '',
          name: name,
          startDate: Timestamp.fromDate(courseDate),
          endDate: Timestamp.fromDate(endDate),
          capacity: capacity,
          subscribed: 0,
          trainerId: trainerId,
        );
        
        await createCourse(newCourse);
        createdCount++;
      }
      
      SnackBarUtils.showSuccessSnackBar(
        context,
        'Creati $createdCount corsi ricorrenti con successo',
      );

      // Torna alla pagina precedente
      Navigator.pop(context, true);
    } catch (e) {
      SnackBarUtils.showErrorSnackBar(
        context,
        'Errore durante la creazione dei corsi ricorrenti',
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final courseDates = _calculateCourseDates();
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Crea Corsi Ricorrenti'),
        backgroundColor: backgroundColor,
        foregroundColor: onPrimaryColor,
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

                // Selezione Data di Inizio
                Card(
                  color: surfaceVariantColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Data di Inizio',
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
                              onPressed: _selectStartDate,
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

                // Selezione Data di Fine
                Card(
                  color: surfaceVariantColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Data di Fine Programazione',
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
                                    endDate != null 
                                      ? DateFormat('dd/MM/yyyy').format(endDate!)
                                      : 'Non selezionata',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _selectEndDate,
                              icon: const Icon(Icons.calendar_today),
                              label: const Text('Seleziona Data'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Selezione Giorni della Settimana
                Card(
                  color: surfaceVariantColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Giorni della Settimana',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...selectedDays.entries.map((entry) {
                          return CheckboxListTile(
                            title: Text(dayNames[entry.key]!),
                            value: entry.value,
                            onChanged: (bool? value) {
                              _toggleDay(entry.key);
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Campo Durata
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
                const SizedBox(height: 20),

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
                    color: surfaceVariantColor,
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

                // Preview dei corsi
                                // Preview dei corsi
                if (courseDates.isNotEmpty) ...[
                  Card(
                    color: surfaceVariantColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Preview: ${courseDates.length} corsi verranno creati',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Dal ${DateFormat('dd/MM/yyyy').format(startDate!)} al ${DateFormat('dd/MM/yyyy').format(endDate!)}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Giorni: ${selectedDays.entries.where((e) => e.value).map((e) => dayNames[e.key]).join(', ')}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Date dei corsi:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: courseDates.length,
                              itemBuilder: (context, index) {
                                final date = courseDates[index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        size: 16,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${_getDayName(date)} ${DateFormat('dd/MM/yyyy').format(date)} alle ${DateFormat('HH:mm').format(date)}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
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
                        onPressed: isLoading ? null : _createRecurringCourses,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text('Crea ${courseDates.length} Corsi'),
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