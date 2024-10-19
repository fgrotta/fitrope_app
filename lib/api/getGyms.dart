import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/gym.dart';

Future<List<Gym>> getGyms() async {
  CollectionReference collectionRef = FirebaseFirestore.instance.collection('gyms');
  QuerySnapshot querySnapshot = await collectionRef.get();

  List<Gym> gyms = [];

  for (QueryDocumentSnapshot doc in querySnapshot.docs) {
    Gym gym = Gym.fromJson(doc.data() as Map<String, dynamic>);
    gyms.add(gym);
  }

  return gyms;
}