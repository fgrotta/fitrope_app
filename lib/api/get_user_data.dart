import 'package:cloud_firestore/cloud_firestore.dart';

Future<Map<String, dynamic>?> getUserData(
  String uid, {
  FirebaseFirestore? firestore,
}) async {
  DocumentSnapshot userDoc = await (firestore ?? FirebaseFirestore.instance)
      .collection('users')
      .doc(uid)
      .get();

  if (userDoc.exists) {
    Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
    return userData;
  } else {
    return null;
  }
}
