import 'package:fitrope_app/api/courses/UnsubscribeToCourse.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/api/courses/subscribeToCourse.dart';
import 'package:fitrope_app/api/courses/createCourse.dart';
import 'package:fitrope_app/api/courses/deleteCourse.dart';
import 'package:fitrope_app/api/courses/updateCourse.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/components/loader.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/utils/getCourseTimeRange.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/calendar.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime firstDate = DateTime(DateTime.now().year);
  DateTime lastDate = DateTime(DateTime.now().year + 1);
  List<Course> courses = [];
  Map<String, List<Course>> coursesByDate = {};
  List<Course> selectedCourses = [];
  late FitropeUser user;
  late DateTime currentDate;
  var pattern = "yyyy-MM-dd";
  final defaultTimeOfDay = const TimeOfDay(hour: 19, minute: 0);
  
  @override
  void initState() {
    user = store.state.user!;
    
    getAllCourses().then((List<Course> response) {
      setState(() {
        courses = response;
        for(Course course in courses) {
          addCourseToMap(course);
        }
        onSelectDate(DateTime.now());
      });
    });
    super.initState();
  }

  void addCourseToMap(Course course) {
    DateTime courseDate = DateTime.fromMillisecondsSinceEpoch(course.startDate.millisecondsSinceEpoch);
    String indexDate = DateFormat(pattern).format(courseDate);
    if(!coursesByDate.containsKey(indexDate)) {
      coursesByDate[indexDate] = [];
    }
    coursesByDate[indexDate]!.add(course);
  }

  void updateCourses() {
    getAllCourses().then((List<Course> response) {
      if(mounted) { 
        setState(() {
          courses = response;
          onSelectDate(currentDate);
          store.dispatch(SetAllCoursesAction(response));
        });
      }
    });
  }

  void onSelectDate(DateTime selectedDate) {
    currentDate = selectedDate;
    selectedCourses = [];
    String indexDate = DateFormat(pattern).format(selectedDate);
    if (coursesByDate[indexDate]!=null){
      selectedCourses = coursesByDate[indexDate]!;
      for(Course course in selectedCourses) {
        print(course.id);
      }
    } 

    setState(() { });
  }

  void onSubscribe(Course course) {
    subscribeToCourse(course.id, user.uid).then((_) {
      setState(() { 
        user = store.state.user!;
        updateCourses();
      });
    });
  }

  void onUnsubscribe(Course course) {
    unsubscribeToCourse(course.id, user.uid).then((_) {
      setState(() { 
        user = store.state.user!;
        updateCourses();
      });
    });
  }

  Future<List<String>> getSubscriberNames(String courseId) async {
    var usersCollection = FirebaseFirestore.instance.collection('users');
    var snapshots = await usersCollection.where('courses', arrayContains: courseId).get();
    return snapshots.docs.map((doc) => "${doc['name']} ${doc['lastName']}").toList();
  }

  void showCourseDialog({
    required String title,
    required String actionButtonText,
    Course? courseToEdit,
    Course? courseToDuplicate,
  }) {
    final nameController = TextEditingController(
      text: courseToEdit?.name ?? courseToDuplicate?.name ?? ''
    );
    final durationController = TextEditingController(
      text: courseToEdit != null 
        ? (courseToEdit.endDate.toDate().difference(courseToEdit.startDate.toDate()).inHours).toString()
        : courseToDuplicate != null 
          ? (courseToDuplicate.endDate.toDate().difference(courseToDuplicate.startDate.toDate()).inHours).toString()
          : '1'
    );
    final capacityController = TextEditingController(
      text: courseToEdit?.capacity.toString() ?? courseToDuplicate?.capacity.toString() ?? '6'
    );
    
    DateTime? startDate = courseToEdit?.startDate.toDate() ?? courseToDuplicate?.startDate.toDate() ?? currentDate;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nome corso'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Data: '),
                        Text(startDate != null ? DateFormat('dd/MM/yyyy').format(startDate!) : 'Non selezionata'),
                        IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialEntryMode: DatePickerEntryMode.calendar,
                              initialDate: startDate ?? DateTime(currentDate.year, currentDate.month, currentDate.day, defaultTimeOfDay.hour, defaultTimeOfDay.minute),
                              firstDate: DateTime.now(),
                              lastDate: DateTime(DateTime.now().year + 1),
                            );
                            if (picked != null) {
                              setStateDialog(() {
                                startDate = DateTime(picked.year, picked.month, picked.day, startDate?.hour ?? defaultTimeOfDay.hour, startDate?.minute ?? defaultTimeOfDay.minute);
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Ora: '),
                        Text(startDate != null ? DateFormat('HH:mm').format(startDate!) : 'Non selezionata'),
                        IconButton(
                          icon: const Icon(Icons.access_time),
                          onPressed: () async {
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
                              setStateDialog(() {
                                startDate = DateTime(startDate?.year ?? currentDate.year, startDate?.month ?? currentDate.month, startDate?.day ?? currentDate.day, pickedTime.hour, pickedTime.minute);
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    // Mostra il campo durata solo per creazione e duplicazione
                    if (courseToEdit == null)
                      TextField(
                        controller: durationController,
                        decoration: const InputDecoration(labelText: 'Durata (ore)'),
                        keyboardType: TextInputType.number,
                      ),
                    TextField(
                      controller: capacityController,
                      decoration: const InputDecoration(labelText: 'Numero massimo partecipanti'),
                      keyboardType: TextInputType.number,
                    ),
                    if (errorMsg != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(errorMsg!, style: const TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annulla'),
                ),
                TextButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final duration = double.tryParse(durationController.text.trim()) ?? 0;
                    final capacity = int.tryParse(capacityController.text.trim()) ?? 0;
                    
                    if (name.isEmpty || startDate == null || capacity <= 0) {
                      setStateDialog(() { errorMsg = 'Compila tutti i campi correttamente'; });
                      return;
                    }
                    
                    if (courseToEdit == null && duration <= 0) {
                      setStateDialog(() { errorMsg = 'Compila tutti i campi correttamente'; });
                      return;
                    }
                    
                    final endDate = startDate!.add(Duration(hours: duration.toInt()));
                    
                    if (courseToEdit != null) {
                      // Modifica corso esistente
                      final updatedCourse = Course(
                        id: courseToEdit.id,
                        name: name,
                        startDate: Timestamp.fromDate(startDate!),
                        endDate: Timestamp.fromDate(endDate),
                        capacity: capacity,
                        subscribed: courseToEdit.subscribed,
                        subscribers: courseToEdit.subscribers,
                      );
                      
                      await updateCourse(updatedCourse);
                      Navigator.pop(context);
                      updateCourses();
                    } else {
                      // Crea nuovo corso (creazione o duplicazione)
                      final newCourse = Course(
                        id: '',
                        name: name,
                        startDate: Timestamp.fromDate(startDate!),
                        endDate: Timestamp.fromDate(endDate),
                        capacity: capacity,
                        subscribed: 0,
                      );
                      
                      await createCourse(newCourse);
                      Navigator.pop(context);
                      updateCourses();
                      addCourseToMap(newCourse);
                    }
                  },
                  child: Text(actionButtonText),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Wrapper functions per mantenere la compatibilità
  void showCreateCourseDialog() {
    showCourseDialog(
      title: 'Crea Nuovo Corso',
      actionButtonText: 'Crea',
    );
  }

  void showDuplicateCourseDialog(Course originalCourse) {
    showCourseDialog(
      title: 'Duplica Corso',
      actionButtonText: 'Duplica',
      courseToDuplicate: originalCourse,
    );
  }

  void showEditCourseDialog(Course course) {
    showCourseDialog(
      title: 'Modifica Corso',
      actionButtonText: 'Salva',
      courseToEdit: course,
    );
  }

  void deleteCourseAndUpdate(Course course) async {
    await deleteCourse(course.id);
    updateCourses();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(
      converter: (store) => store.state,
      builder: (context, state) {
        return Stack(
            children: [
            SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding, top: pagePadding + MediaQuery.of(context).viewPadding.top),
                      child: const Text('Calendario corsi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30, color: Colors.white),),
                    ),
                    Theme(
                      data: ThemeData(
                        colorScheme: const ColorScheme.light(
                          onSurface: Colors.white
                        ),
                        datePickerTheme: DatePickerThemeData(
                          dayForegroundColor: WidgetStateProperty.all(Colors.white),
                          weekdayStyle: const TextStyle(color: Colors.white),
                          headerHeadlineStyle: const TextStyle(color: Colors.white),
                          todayForegroundColor: WidgetStateProperty.all(Colors.white),
                          todayBackgroundColor: WidgetStateProperty.all(const Color.fromARGB(255, 90, 90, 90)),
                          yearOverlayColor: WidgetStateProperty.all(ghostColor),
                          yearBackgroundColor: WidgetStateProperty.all(primaryColor),
                          yearForegroundColor: WidgetStateProperty.all(Colors.white),
                          dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return const Color.fromARGB(255, 100, 100, 100);
                            }
                            return null;
                          }),)
                      ), 
                      child: Calendar(
                        onDateChanged: (DateTime value) { 
                          onSelectDate(value);
                        }, 
                        initialDate: DateTime.now(), 
                        firstDate: firstDate, 
                        lastDate: lastDate,
                        filledDays: courses.map((Course course) => course.startDate.toDate()).toList()
                      ),
                    ),
                    
                    Padding(
                      padding: const EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding),
                      child: Column(
                          children: selectedCourses.isNotEmpty ? selectedCourses.map(
                            (Course course) => FutureBuilder<List<String>>(
                              future: getSubscriberNames(course.id),
                              builder: (context, snapshot) {
                                String iscritti = "";
                                List<String> names = [];
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  iscritti = "Caricamento iscritti...";
                                } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                                  iscritti = "Iscritti: " + snapshot.data!.join(", ");
                                  names = snapshot.data!;
                                } else {
                                  iscritti = "Nessun iscritto";
                                }
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10), 
                                  child: CourseCard(
                                    courseId: course.id,
                                    title: course.name, 
                                    description: getCourseTimeRange(course) + "\n" + iscritti,
                                    courseState: getCourseState(course, user),
                                    onClickAction: () {
                                      CourseState courseState = getCourseState(course, user);
                                      if(courseState == CourseState.SUBSCRIBED) {
                                        onUnsubscribe(course);
                                      }
                                      else {
                                        onSubscribe(course);
                                      }              
                                    },
                                    capacity: course.capacity,
                                    subscribed: course.subscribed,
                                    subscribersNames: names,
                                    isAdmin: user.role == 'Admin',
                                    onDuplicate: () => showDuplicateCourseDialog(course),
                                    onDelete: () => deleteCourseAndUpdate(course),
                                    onEdit: () => showEditCourseDialog(course),
                                  )
                                );
                              },
                            )
                          ).toList() : [
                            const Text('Nessun corso disponibile in questa giornata', style: TextStyle(color: ghostColor),)
                        ],
                      ),
                    ),
                    if (user.role == 'Admin') 
                      Padding(
                        padding: const EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding),
                        child: ElevatedButton(
                          onPressed: showCreateCourseDialog,
                          child: const Text('Crea nuovo corso'),
                        ),
                      ),
                  ],
                ),
              ),
            if (state.isLoading) const Loader(),
          ]
        );
      }
    );
  }
}