import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/formatDate.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/utils/getCourseTimeRange.dart';
import 'package:fitrope_app/utils/getTipologiaIscrizioneLabel.dart';
import 'package:fitrope_app/utils/user_display_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/custom_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late FitropeUser user;
  List<Course> allCourses = [];
List<FitropeUser> trainers = [];
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
        if(mounted) {
          allCourses = response;
          store.dispatch(SetAllCoursesAction(response));
        }
      });
    });
    
    super.initState();
  }

  Widget renderSubscriptionCard() {
    if(
      user.tipologiaIscrizione != TipologiaIscrizione.ABBONAMENTO_MENSILE &&
      user.tipologiaIscrizione != TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE &&
      user.tipologiaIscrizione != TipologiaIscrizione.PACCHETTO_ENTRATE
    ) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 20, bottom: 10),
            width: double.infinity,
            child: const Text('Il mio abbonamento', textAlign: TextAlign.left, style: TextStyle(color: Colors.white, fontSize: 20),),
          ),
          const SizedBox(height: 20,),
          const Text('Nessun abbonamento disponibile', style: TextStyle(color: ghostColor),),
          const SizedBox(height: 30,),
        ],
      );
    }

    bool isExpired = false;
    int today = DateTime.now().millisecondsSinceEpoch;

    if(
      (user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_MENSILE ||
      user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE) &&
      user.fineIscrizione != null && 
      today > user.fineIscrizione!.toDate().millisecondsSinceEpoch
    ) {
      isExpired = true;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          width: double.infinity,
          child: const Text('Il mio abbonamento', textAlign: TextAlign.left, style: TextStyle(color: Colors.white, fontSize: 20),),
        ),
        CustomCard(title: getTipologiaIscrizioneTitle(user.tipologiaIscrizione!, isExpired), description: getTipologiaIscrizioneDescription(user),),
        const SizedBox(height: 30,),
      ],
    );
  }
//TODO: Muovere in utils e spostare Get Users nella API, e aggiungere Cache
  Future<List<String>> getSubscriberNames(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    var usersCollection = FirebaseFirestore.instance.collection('users');
    var snapshots = await usersCollection.where('uid', whereIn: userIds).get();
    return snapshots.docs.map((doc) {
      final user = FitropeUser.fromJson(doc.data());
      return UserDisplayUtils.getDisplayName(user, user.role == 'Admin');
    }).toList();
  }

  List<Widget> renderCourses() {
    if(user.courses.isEmpty) {
      return [
        const SizedBox(height: 10,),
        const Text('Nessun corso disponibile', style: TextStyle(color: ghostColor),)
      ];
    }

    List<Widget> render = [];

    for(int n=0;n<user.courses.length;n++) {
      Course? course = allCourses.where((Course course) => course.id == user.courses[n]).firstOrNull;

      if(course != null && getCourseState(course, user) != CourseState.EXPIRED) {
        DateTime courseDate = DateTime.fromMillisecondsSinceEpoch(course.startDate.millisecondsSinceEpoch);

        render.add(
          FutureBuilder<List<String>>(
            future: getSubscriberNames(course.subscribers),
            builder: (context, snapshot) {
              String iscritti = "";
              String trainer = "Trainer: " + UserDisplayUtils.getTrainerName(course.trainerId, trainers);
              if (snapshot.connectionState == ConnectionState.waiting) {
                iscritti = "Iscritti: Caricamento iscritti...";
              } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                iscritti = "Iscritti:\n" + snapshot.data!.join("\n");
              } else {
                iscritti = "Iscritti: Nessun iscritto";
              }
              
              return Container(
                margin: const EdgeInsets.only(bottom: 10), 
                child: CourseCard(
                  courseId: course.id,
                  title: course.name, 
                  description: "${formatDate(courseDate)}, ${getCourseTimeRange(course)}\n$trainer\n$iscritti",
                  capacity: course.capacity,
                  subscribed: course.subscribed,
                )
              );
            },
          )
        );
      }
    }

    if(render.isEmpty) {
      return [
        const SizedBox(height: 10,),
        const Text('Nessun corso disponibile', style: TextStyle(color: ghostColor),)
      ];
    }

    return render;
  }
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding, top: pagePadding + MediaQuery.of(context).viewPadding.top),
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
                    MaterialPageRoute(builder: (context) => UserDetailPage(user: user)),
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