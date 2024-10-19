import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/gym.dart';

Future<List<Gym>> getGyms() async {
  print('CCCCCCCCC');
  CollectionReference collectionRef = FirebaseFirestore.instance.collection('gyms');
  QuerySnapshot querySnapshot = await collectionRef.get();

  List<Gym> gyms = [];

  print('BBBB');

  for (QueryDocumentSnapshot doc in querySnapshot.docs) {
    print(doc.data());
    print('AAAAAAAAA');
    Gym gym = Gym.fromJson(doc.data() as Map<String, dynamic>);
    gyms.add(gym);
  }

  return gyms;
}