import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/types/gym.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/utils/getCourseTimeRange.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/calendar.dart';

class GymDetail extends StatefulWidget {
  final Gym gym;
  const GymDetail({super.key, required this.gym});

  @override
  State<GymDetail> createState() => _GymDetailState();
}

class _GymDetailState extends State<GymDetail> {
  DateTime firstDate = DateTime(DateTime.now().year);
  DateTime lastDate = DateTime(DateTime.now().year + 2);
  List<Course> courses = [];
  List<Course> selectedCourses = [];
  late FitropeUser user;

  @override
  void initState() {
    user = store.state.user!;
    
    getCourses(widget.gym.id).then((List<Course> response) {
      setState(() {
        courses = response;
        onSelectDate(DateTime.now());
      });
    });
    super.initState();
  }

  void onSelectDate(DateTime selectedDate) {
    selectedCourses = [];

    for(int n=0;n<courses.length;n++) {
      DateTime courseDate = DateTime.fromMillisecondsSinceEpoch(courses[n].startDate.millisecondsSinceEpoch);
      if(selectedDate.year == courseDate.year && selectedDate.month == courseDate.month && selectedDate.day == courseDate.day) {
        selectedCourses.add(courses[n]);
      }
    }

    setState(() { });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.gym.name, style: const TextStyle(color: Colors.white),),
      ),
      backgroundColor: backgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Theme(
              data: ThemeData(
                datePickerTheme: DatePickerThemeData(
                  dayForegroundColor: WidgetStateProperty.all(Colors.white),
                  weekdayStyle: const TextStyle(color: Colors.white),
                  headerHeadlineStyle: const TextStyle(color: Colors.white),
                  todayForegroundColor: WidgetStateProperty.all(Colors.white),
                  todayBackgroundColor: WidgetStateProperty.all(const Color.fromARGB(255, 90, 90, 90)),
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding),
              child: Column(
                children: selectedCourses.map(
                  (Course course) => Container(
                    margin: const EdgeInsets.only(bottom: 10), 
                    child: CourseCard(
                      title: course.name, 
                      description: getCourseTimeRange(course),
                      courseState: getCourseState(course, user),
                    )
                  )
                ).toList(),
              ),
            )
          ],
        ),
      ),
    );
  }
}