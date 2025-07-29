import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/formatDate.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/utils/getCourseTimeRange.dart';
import 'package:fitrope_app/utils/user_display_utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CoursePreviewCard extends StatelessWidget {
  final Course course;
  final FitropeUser currentUser;
  final List<FitropeUser> trainers;
  final VoidCallback? onSubscribe;
  final VoidCallback? onUnsubscribe;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final bool showDate;

  const CoursePreviewCard({
    super.key,
    required this.course,
    required this.currentUser,
    required this.trainers,
    this.onSubscribe,
    this.onUnsubscribe,
    this.onDuplicate,
    this.onDelete,
    this.onEdit,
    this.showDate = true,
  });

  Future<List<String>> getSubscriberNames(String courseId, bool isAdmin) async {
    var usersCollection = FirebaseFirestore.instance.collection('users');
    //TODO: Forse si può Ottimizzare per usare la cache, ma non è urgente
    var snapshots = await usersCollection.where('courses', arrayContains: courseId).get();
    return snapshots.docs.map((doc) {
      final user = FitropeUser.fromJson(doc.data());
      // Gli admin vedono sempre i nomi completi, con icona fantasma per gli anonimi
      return UserDisplayUtils.getDisplayName(user, isAdmin);
    }).toList();
  }

  String _buildDescription() {
    final trainer = "Trainer: ${UserDisplayUtils.getTrainerName(course.trainerId, trainers)}";
    
    if (showDate) {
      final courseDate = DateTime.fromMillisecondsSinceEpoch(course.startDate.millisecondsSinceEpoch);
      return "${formatDate(courseDate)}, ${getCourseTimeRange(course)}\n$trainer";
    } else {
      return "${getCourseTimeRange(course)}\n$trainer";
    }
  }

  @override
  Widget build(BuildContext context) {
    print(course.id);
    print(currentUser.role);
    return FutureBuilder<List<String>>(
      future: getSubscriberNames(course.id, currentUser.role == 'Admin'),
      builder: (context, snapshot) {
        String iscritti = "";
        List<String> names = [];
        
        if (snapshot.connectionState == ConnectionState.waiting) {
          iscritti = "Iscritti: Caricamento iscritti...";
        } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          iscritti = "Iscritti:\n${snapshot.data!.join("\n")}";
          names = snapshot.data!;
        } else {
          iscritti = "Iscritti: Nessun iscritto";
        }

        final description = "${_buildDescription()}\n$iscritti";
        final courseState = getCourseState(course, currentUser);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: CourseCard(
            courseId: course.id,
            title: course.name,
            description: description,
            courseState: courseState,
            onClickAction: () {
              if (courseState == CourseState.SUBSCRIBED) {
                onUnsubscribe?.call();
              } else {
                onSubscribe?.call();
              }
            },
            capacity: course.capacity,
            subscribed: course.subscribed,
            subscribersNames: names,
            isAdmin: currentUser.role == 'Admin',
            onDuplicate: onDuplicate,
            onDelete: onDelete,
            onEdit: onEdit,
          ),
        );
      },
    );
  }
} 