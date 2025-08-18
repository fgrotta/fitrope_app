import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/api/courses/subscribeToCourse.dart';
import 'package:fitrope_app/api/courses/unsubscribeToCourse.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/components/course_preview_card.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/utils/getTipologiaIscrizioneLabel.dart';
import 'package:fitrope_app/utils/course_unsubscribe_helper.dart';
import 'package:fitrope_app/components/course_card.dart';
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

  // Funzione per aggiornare i corsi e lo stato utente
  void refreshCourses() {
    getAllCourses().then((List<Course> response) {
      if(mounted) {
        setState(() {
          allCourses = response;
          store.dispatch(SetAllCoursesAction(response));
        });
      }
    });
    
    // Aggiorna anche lo stato utente per riflettere le modifiche
    if (store.state.user != null) {
      getUserData(user.uid).then((userData) {
        if (userData != null && mounted) {
          setState(() {
            user = FitropeUser.fromJson(userData);
          });
          store.dispatch(SetUserAction(user));
        }
      });
    }
  }

  // Callback per l'iscrizione
  void onSubscribe(Course course) {
    print('🔄 Iscrizione al corso: ${course.name}');
    subscribeToCourse(course.uid, user.uid).then((_) {
      print('✅ Iscrizione completata');
      refreshCourses();
    }).catchError((e) {
      print('❌ Errore durante l\'iscrizione: $e');
      // Mostra snackbar di errore
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante l\'iscrizione: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  // Callback per la disiscrizione
  void onUnsubscribe(Course course) {
    print('🔄 Disiscrizione dal corso: ${course.name}');
    // Usa il nuovo sistema di disiscrizione intelligente
    CourseUnsubscribeHelper.handleUnsubscribe(course, user, context).then((success) {
      if (success) {
        print('✅ Disiscrizione completata');
        refreshCourses();
        
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
      }
    }).catchError((e) {
      print('❌ Errore durante la disiscrizione: $e');
      // Mostra snackbar di errore
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante la disiscrizione: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
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

  List<Widget> renderCourses() {
    if(user.courses.isEmpty) {
      return [
        const SizedBox(height: 10,),
        const Text('Nessun corso disponibile', style: TextStyle(color: ghostColor),)
      ];
    }

    List<Widget> render = [];

    for(int n=0; n<user.courses.length; n++) {
      // Usa course.uid invece di course.id per la sincronizzazione
      Course? course = allCourses.where((Course course) => course.uid == user.courses[n]).firstOrNull;

      if(course != null && getCourseState(course, user) != CourseState.EXPIRED) {
        render.add(
          CoursePreviewCard(
            course: course,
            currentUser: user,
            trainers: trainers,
            showDate: true,
            onSubscribe: () => onSubscribe(course),
            onUnsubscribe: () => onUnsubscribe(course),
          ),
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