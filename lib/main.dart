import 'package:firebase_core/firebase_core.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'firebase_options.dart';

void main() async {  
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(
    StoreProvider(
      store: store,
      child: const MyApp()
    )
  );


  // tests //
  
  // dynamic gyms = await getGyms();
  // print(gyms[0].name);
  
  // dynamic courses = await getCourses(1);
  // print(courses);
  // dynamic courses2 = await getCourses(2);
  // print(courses2);

  // await createCourse(Course(gymId: 1, name: 'test', startDate: Timestamp.now(), endDate: Timestamp.now(), id: 1, capacity: 3));

  // await subscribeToCourse('asd', 'AC8Q5coVfNRQvpueb6tRoL8gwfO2');

  // tests //
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: INITIAL_ROUTE,
      routes: routes,
    );
  }
}