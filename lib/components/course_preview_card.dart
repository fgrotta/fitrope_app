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
  final VoidCallback onRefresh; // Callback per aggiornare la lista
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
    required this.onRefresh,
    this.showDate = true,
  });

  Future<List<Map<String, dynamic>>> getSubscriberNames(Course course, bool isAdmin) async {
    var usersCollection = FirebaseFirestore.instance.collection('users');
    var snapshots = await usersCollection.where('courses', arrayContains: course.uid).get();
    return snapshots.docs.map((doc) {
      final user = FitropeUser.fromJson(doc.data());
      // Gli admin vedono sempre i nomi completi, con icona fantasma per gli anonimi
      return {
        'displayName': UserDisplayUtils.getDisplayName(user, isAdmin),
        'user': user,
      };
    }).toList();
  }

  String _buildDescription() {
    final trainer = "Trainer: ${UserDisplayUtils.getTrainerName(course.trainerId, trainers)}";
    
    if (showDate) {
      final courseDate = DateTime.fromMillisecondsSinceEpoch(course.startDate.millisecondsSinceEpoch);
      return "Orario: ${formatDate(courseDate)}, ${getCourseTimeRange(course)}\n$trainer";
    } else {
      return "Orario: ${getCourseTimeRange(course)}\n$trainer";
    }
  }

  bool _canViewUserDetails() {
    return currentUser.role == 'Admin' || currentUser.role == 'Trainer';
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: getSubscriberNames(course, _canViewUserDetails()),
      builder: (context, snapshot) {
        String iscritti = "";
        List<String> names = [];
        List<FitropeUser> users = [];
        
        if (snapshot.connectionState == ConnectionState.waiting) {
          iscritti = "Iscritti: Caricamento iscritti...";
        } else if (snapshot.hasData) {
          names = snapshot.data!.map((s) => s['displayName'] as String).toList();
          users = snapshot.data!.map((s) => s['user'] as FitropeUser).toList();
        } else {
          iscritti = "Iscritti: Nessun iscritto";
        }

        final description = "${_buildDescription()}\n$iscritti";
        final courseState = getCourseState(course, currentUser);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: CourseCard(
            courseId: course.uid,
            course: course,
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
            // Passa una lista vuota per Admin e Trainer per evitare la duplicazione
            subscribersNames: _canViewUserDetails() ? [] : names,
            // Passa la lista degli utenti per la versione cliccabile
            subscribersUsers: _canViewUserDetails() ? users : null,
            // Abilita la lista cliccabile per Admin e Trainer
            showClickableSubscribers: _canViewUserDetails(),
            isAdmin: currentUser.role == 'Admin' || currentUser.role == 'Trainer',
            userRole: currentUser.role,
            onDuplicate: onDuplicate,
            onDelete: onDelete,
            onEdit: onEdit,
            onRefresh: onRefresh,
          ),
        );
      },
    );
  }
} 