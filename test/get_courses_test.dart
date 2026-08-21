import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fitrope_app/api/courses/get_courses.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> courseData(String name, {String? id, String? uid}) {
  final start = DateTime.now().add(const Duration(days: 2));
  return {
    if (id != null) 'id': id,
    if (uid != null) 'uid': uid,
    'name': name,
    'startDate': Timestamp.fromDate(start),
    'endDate': Timestamp.fromDate(start.add(const Duration(hours: 1))),
    'capacity': 10,
    'subscribed': 0,
  };
}

void main() {
  test(
    'accetta documenti canonici uid e legacy id, scarta solo senza entrambi',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('courses')
          .doc('canonical-doc')
          .set(courseData('Canonico', uid: 'canonical-uid'));
      await firestore
          .collection('courses')
          .doc('legacy-doc')
          .set(courseData('Legacy', id: 'legacy-id'));
      await firestore
          .collection('courses')
          .doc('invalid-doc')
          .set(courseData('Invalido'));

      final courses = await getAllCourses(firestore: firestore, force: true);

      expect(
        courses.map((course) => course.uid),
        containsAll(<String>['canonical-uid', 'legacy-id']),
      );
      expect(courses, hasLength(2));
    },
  );
}
