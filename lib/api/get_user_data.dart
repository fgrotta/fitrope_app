import 'package:cloud_firestore/cloud_firestore.dart';

Future<Map<String, dynamic>?> getUserData(String uid) async {
  DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

  if (userDoc.exists) {
    Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
    return userData;
  } 
  else {
    return null;
  }
}