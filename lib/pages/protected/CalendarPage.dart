import 'package:fitrope_app/api/courses/unsubscribeToCourse.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/api/courses/subscribeToCourse.dart';
import 'package:fitrope_app/api/courses/deleteCourse.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/components/course_preview_card.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/components/loader.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/calendar.dart';
import 'package:flutter_redux/flutter_redux.dart';
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
  List<FitropeUser> trainers = [];
  Map<String, List<Course>> coursesByDate = {};
  List<Course> selectedCourses = [];
  late FitropeUser user;
  late DateTime currentDate;
  var pattern = "yyyy-MM-dd";
  final defaultTimeOfDay = const TimeOfDay(hour: 19, minute: 0);
  
  @override
  void initState() {
    user = store.state.user!;
    getTrainers().then((List<FitropeUser> response) {
      setState(() {
        trainers = response;
      });
    });
    getAllCourses().then((List<Course> response) {
      setState(() {
        courses = response;
        for(Course course in courses) {
          updateCourseToMap(course, null);
        }
        onSelectDate(DateTime.now());
      });
    });
    super.initState();
  }

  void updateCourseToMap(Course newCourse, Course? oldCourse ) {
    if (oldCourse != null) {
      removeCoruseFromMap(oldCourse);
    }
    DateTime courseDate = DateTime.fromMillisecondsSinceEpoch(newCourse.startDate.millisecondsSinceEpoch);
    String indexDate = DateFormat(pattern).format(courseDate);
    if(!coursesByDate.containsKey(indexDate)) {
      coursesByDate[indexDate] = [];
    }
    coursesByDate[indexDate]!.add(newCourse);
  }

  void removeCoruseFromMap(Course oldCourse) {
    coursesByDate[DateFormat(pattern).format(oldCourse.startDate.toDate())]!.remove(oldCourse);
  }

  void updateCourses() {
    getAllCourses().then((List<Course> response) {
      if(mounted) { 
        setState(() {
          courses = response;
          // Ricostruisci la mappa dei corsi
          coursesByDate.clear();
          for(Course course in courses) {
            updateCourseToMap(course, null);
          }
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
    } 

    setState(() { });
  }

  void onSubscribe(Course course) {
    subscribeToCourse(course.id, user.uid).then((_) {
      setState(() { 
        print('onSubscribe');
        updateCourses();
      });
    });
  }

  void onUnsubscribe(Course course) {
    unsubscribeToCourse(course.id, user.uid).then((_) {
      setState(() { 
        print('onUnsubscribe');
        updateCourses();
      });
    });
  }

  // Funzioni per navigare alla pagina di gestione corsi
  void showCreateCoursePage() {
    Navigator.pushNamed(
      context,
      COURSE_MANAGEMENT_ROUTE,
      arguments: {
        'mode': 'create',
      },
    ).then((result) {
      if (result == true) {
        updateCourses();
      }
    });
  }

  void showDuplicateCoursePage(Course originalCourse) {
    Navigator.pushNamed(
      context,
      COURSE_MANAGEMENT_ROUTE,
      arguments: {
        'mode': 'duplicate',
        'courseToDuplicate': originalCourse,
      },
    ).then((result) {
      if (result == true) {
        updateCourses();
      }
    });
  }

  void showEditCoursPage(Course course) {
    Navigator.pushNamed(
      context,
      COURSE_MANAGEMENT_ROUTE,
      arguments: {
        'mode': 'edit',
        'courseToEdit': course,
      },
    ).then((result) {
      if (result == true) {
        updateCourses();
      }
    });
  }
  
  void showRecurringCoursePage() {
    Navigator.pushNamed(
      context,
      RECURRING_COURSE_ROUTE,
    ).then((result) {
      if (result == true) {
        updateCourses();
      }
    });
  }
  // Funzione di utilità per verificare se un corso è nel futuro
  bool _isCourseInFuture(Course course) {
    return course.startDate.toDate().isAfter(DateTime.now());
  }

  void deleteCourseAndUpdate(Course course) async {
    try {
      await deleteCourse(course.id);
      updateCourses();
      
      // Mostra SnackBar di successo
      SnackBarUtils.showSuccessSnackBar(
        context,
        'Corso cancellato con successo',
      );
    } catch (e) {
      // Mostra SnackBar di errore
      SnackBarUtils.showErrorSnackBar(
        context,
        'Errore durante la cancellazione del corso',
      );
    }
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
                      padding: const EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding, top: pagePadding),
                      child: Column(
                          children: selectedCourses.isNotEmpty ? selectedCourses.map(
                            (Course course) => CoursePreviewCard(
                              course: course,
                              currentUser: user,
                              trainers: trainers,
                              showDate: false,
                              onSubscribe: () => onSubscribe(course),
                              onUnsubscribe: () => onUnsubscribe(course),
                              onDuplicate: () => showDuplicateCoursePage(course),
                              onDelete: user.role == 'Admin' ? () => deleteCourseAndUpdate(course) : null,
                              onEdit: (user.role == 'Admin' || (user.role == 'Trainer' && (course.trainerId == null || course.trainerId == user.uid))) 
                                ? (_isCourseInFuture(course) ? () => showEditCoursPage(course) : null)
                                : null,
                            ),
                          ).toList() : [
                            const Text('Nessun corso disponibile in questa giornata', style: TextStyle(color: ghostColor),)
                        ],
                      ),
                    ),
                    if (user.role == 'Admin' || user.role == 'Trainer') ...[
                      Padding(
                        padding: const EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: showCreateCoursePage,
                                child: const Text('Crea nuovo corso'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: showRecurringCoursePage,
                                icon: const Icon(Icons.repeat),
                                label: const Text('Corsi ricorrenti'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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