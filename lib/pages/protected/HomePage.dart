import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/formatDate.dart';
import 'package:fitrope_app/utils/getCourseTimeRange.dart';
import 'package:fitrope_app/utils/getTipologiaIscrizioneLabel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/custom_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late FitropeUser user;
  List<Course> allCourses = [];

  @override
  void initState() {
    user = store.state.user!;

    getAllCourses().then((List<Course> response) {
      setState(() {
        allCourses = response;
      });
    });

    super.initState();
  }

  Widget renderSubscriptionCard() {
    if(user.tipologiaIscrizione == null) {
      return const Text('Nessun abbonamento disponibile');
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          width: double.infinity,
          child: const Text('Il mio abbonamento', textAlign: TextAlign.left, style: TextStyle(color: Colors.white, fontSize: 20),),
        ),
        CustomCard(title: getTipologiaIscrizioneLabel(user.tipologiaIscrizione!), description: 'Entrate disponibili: ${user.entrateDisponibili}',),
        const SizedBox(height: 30,),
      ],
    );
  }

  List<Widget> renderCourses() {
    List<Widget> render = [];

    for(int n=0;n<user.courses.length;n++) {
      Course? course = allCourses.where((Course course) => course.id == user.courses[n]).firstOrNull;

      if(course != null) {
        DateTime courseDate = DateTime.fromMillisecondsSinceEpoch(course.startDate.millisecondsSinceEpoch);

        render.add(
          Container(
            margin: const EdgeInsets.only(bottom: 10), 
            child: CourseCard(
              title: course.name, 
              description: "${formatDate(courseDate)}, ${getCourseTimeRange(course)}"
            )
          )
        );
      }
    }

    return render;
  }
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(pagePadding),
      child: Column(
        children: [
          // HEADER
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Home', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30, color: Colors.white),),
              GestureDetector(
                child: CircleAvatar(
                  backgroundColor: const Color.fromARGB(255, 113, 129, 219),
                  child: Text(user.name[0] + user.lastName[0]),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const UserDetailPage()),
                  );
                },
              )
            ],
          ),

          // ABBONAMENTO
          renderSubscriptionCard(),

          // CORSI
          Column(
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 10),
                width: double.infinity,
                child: const Text('I miei corsi', textAlign: TextAlign.left, style: TextStyle(color: Colors.white, fontSize: 20),),
              ),
              ...renderCourses()
            ],
          ),
        ],
      ),
    );
  }
}