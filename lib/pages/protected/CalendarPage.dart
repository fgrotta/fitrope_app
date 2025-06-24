import 'package:fitrope_app/api/courses/UnsubscribeToCourse.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/api/courses/subscribeToCourse.dart';
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

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime firstDate = DateTime(DateTime.now().year);
  DateTime lastDate = DateTime(DateTime.now().year + 2);
  List<Course> courses = [];
  List<Course> selectedCourses = [];
  late FitropeUser user;
  late DateTime currentDate;

  @override
  void initState() {
    user = store.state.user!;
    
    getAllCourses().then((List<Course> response) {
      setState(() {
        courses = response;
        onSelectDate(DateTime.now());
      });
    });
    super.initState();
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

    for(int n=0;n<courses.length;n++) {
      DateTime courseDate = DateTime.fromMillisecondsSinceEpoch(courses[n].startDate.millisecondsSinceEpoch);
      if(selectedDate.year == courseDate.year && selectedDate.month == courseDate.month && selectedDate.day == courseDate.day) {
        selectedCourses.add(courses[n]);
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

  Future<List<String>> getSubscriberNames(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    var usersCollection = FirebaseFirestore.instance.collection('users');
    var snapshots = await usersCollection.where('uid', whereIn: userIds).get();
    return snapshots.docs.map((doc) => "${doc['name']} ${doc['lastName']}").toList();
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
                          future: getSubscriberNames(course.subscribers),
                          builder: (context, snapshot) {
                            String iscritti = "";
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              iscritti = "Caricamento iscritti...";
                            } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                              iscritti = "Iscritti: " + snapshot.data!.join(", ");
                            } else {
                              iscritti = "Nessun iscritto";
                            }
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10), 
                              child: CourseCard(
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
                              )
                            );
                          },
                        )
                      ).toList() : [
                        const Text('Nessun corso disponibile in questa giornata', style: TextStyle(color: ghostColor),)
                      ],
                    ),
                  )
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