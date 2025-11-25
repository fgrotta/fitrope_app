import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/api/courses/subscribeToCourse.dart';
import 'package:fitrope_app/api/courses/deleteCourse.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/components/course_preview_card.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/utils/course_unsubscribe_helper.dart';
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
        refreshCourseMap(response);
        onSelectDate(DateTime.now());
      });
    });
    super.initState();
  }

  void refreshCourseMap(List<Course> response) {
    coursesByDate.clear();
    store.dispatch(SetAllCoursesAction(response));    
    courses = response;
    for(Course course in response) {
      updateCourseToMap(course, null);
    }
    
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
    invalidateUsersCache();
    user = store.state.user!;
    invalidateCoursesCache();
    selectedCourses = [];
    getAllCourses().then((List<Course> response) {
      if(mounted) { 
        refreshCourseMap(response);
        onSelectDate(currentDate);
        store.dispatch(SetAllCoursesAction(response));
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
    subscribeToCourse(course.uid, user.uid).then((_) {
      setState(() { 
        updateCourses();
      });
    });
  }

  void onUnsubscribe(Course course) async {
    try {
      print('🔄 Inizio disiscrizione per corso: ${course.name}');
      
      // Usa il nuovo sistema di disiscrizione intelligente
      bool success = await CourseUnsubscribeHelper.handleUnsubscribe(
        course,
        user,
        context,
      );
      
      if (success) {
        print('✅ Disiscrizione completata con successo');
        
        // Aggiorna lo stato dell'utente corrente
        if (store.state.user != null && store.state.user!.uid == user.uid) {
          // Ricarica i dati utente per aggiornare entrateDisponibili e courses
          try {
            print('🔄 Aggiornamento stato utente nello store');
            final userData = await getUserData(user.uid);
            if (userData != null) {
              store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
            }
          } catch (e) {
            print('⚠️ Errore nell\'aggiornamento stato utente: $e');
          }
        }
        updateCourses();
        // Mostra messaggio di successo
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Disiscrizione completata con successo'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('❌ Disiscrizione annullata dall\'utente');
        // L'utente ha annullato la disiscrizione, non fare nulla
      }
      
    } catch (e) {
      print('❌ Errore durante la disiscrizione: $e');
      SnackBarUtils.showErrorSnackBar(
        context,
        'Errore durante la disiscrizione: ${e.toString()}',
      );
    }
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
      await deleteCourse(course.uid);
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
              padding: EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding, top: pagePadding + MediaQuery.of(context).viewPadding.top),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Image(image: AssetImage('assets/new_logo_only.png'), width: 30,),
                          const Text('Calendario corsi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30, color: onPrimaryColor),),
                          GestureDetector(
                          child: CircleAvatar(
                          backgroundColor: const Color.fromARGB(255, 96, 119, 246),
                          child: Text(user.name[0] + user.lastName[0]),
                            ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => UserDetailPage(user: user)),
                            );
                          }),
                        ],
                      ),
                    Theme(
                      data: ThemeData(
                        colorScheme: const ColorScheme.highContrastDark(
                          onSurface: onPrimaryColor
                        ),
                        datePickerTheme: DatePickerThemeData(
                          dayForegroundColor: WidgetStateProperty.all(onSurfaceColor),
                          weekdayStyle: const TextStyle(color: onPrimaryColor),
                          headerHeadlineStyle: const TextStyle(color: onPrimaryColor),
                          todayForegroundColor: WidgetStateProperty.all(onPrimaryColor),
                          todayBackgroundColor: WidgetStateProperty.all(onSurfaceVariantColorTrasparent),
                          yearOverlayColor: WidgetStateProperty.all(surfaceVariantColor),
                          yearBackgroundColor: WidgetStateProperty.all(primaryLightColor),
                          yearForegroundColor: WidgetStateProperty.all(onPrimaryColor),
                          dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return primaryLightColor;
                            }
                            return null;
                          }),
                        ),
                          
                      ), 
                      child: Calendar(
                        onDateChanged: (DateTime value) { 
                          onSelectDate(value);
                        }, 
                        initialDate: DateTime.now(), 
                        firstDate: firstDate, 
                        lastDate: lastDate,
                        filledDays: courses.map((Course course) => course.startDate.toDate()).toList(),
                      ),
                    ),
                    
                    Padding(
                      padding: const EdgeInsets.all(10),
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
                              onRefresh: () => updateCourses(),
                            ),
                          ).toList() : [
                            const Text('Nessun corso disponibile in questa giornata', style: TextStyle(color: onPrimaryColor),)
                        ],
                      ),
                    ),
                    if (user.role == 'Admin' || user.role == 'Trainer') ...[
                      Padding(
                        padding: const EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: showCreateCoursePage,
                                icon: const Icon(Icons.add, color: onPrimaryColor,),
                                label: const Text('Crea nuovo corso', style: TextStyle(color: onPrimaryColor),),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: surfaceVariantColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: showRecurringCoursePage,
                                icon: const Icon(Icons.repeat, color: onPrimaryColor,),
                                label: const Text('Corsi ricorrenti', style: TextStyle(color: onPrimaryColor),),
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