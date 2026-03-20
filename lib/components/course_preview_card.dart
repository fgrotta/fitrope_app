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
  final VoidCallback? onJoinWaitlist;
  final VoidCallback? onLeaveWaitlist;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback onRefresh;
  final bool showDate;

  const CoursePreviewCard({
    super.key,
    required this.course,
    required this.currentUser,
    required this.trainers,
    this.onSubscribe,
    this.onUnsubscribe,
    this.onJoinWaitlist,
    this.onLeaveWaitlist,
    this.onDuplicate,
    this.onDelete,
    this.onEdit,
    required this.onRefresh,
    this.showDate = true,
  });

  Future<Map<String, List<Map<String, dynamic>>>> getCourseUsers(Course course, bool isAdmin) async {
    var usersCollection = FirebaseFirestore.instance.collection('users');

    var subscriberSnapshots = await usersCollection.where('courses', arrayContains: course.uid).get();
    final subscribers = subscriberSnapshots.docs.map((doc) {
      final user = FitropeUser.fromJson(doc.data());
      return {
        'displayName': UserDisplayUtils.getDisplayName(user, isAdmin),
        'user': user,
      };
    }).toList();

    List<Map<String, dynamic>> waitlistUsers = [];
    if (course.waitlist.isNotEmpty && isAdmin) {
      var waitlistSnapshots = await usersCollection.where('waitlistCourses', arrayContains: course.uid).get();
      waitlistUsers = waitlistSnapshots.docs.map((doc) {
        final user = FitropeUser.fromJson(doc.data());
        return {
          'displayName': UserDisplayUtils.getDisplayName(user, isAdmin),
          'user': user,
        };
      }).toList();
    }

    return {'subscribers': subscribers, 'waitlistUsers': waitlistUsers};
  }

  String _buildDescription() {
    final trainer = "Trainer: ${UserDisplayUtils.getTrainerName(course.trainerId, trainers)}";
    
    if (showDate) {
      final courseDate = DateTime.fromMillisecondsSinceEpoch(course.startDate.millisecondsSinceEpoch);
      return "Orario: ${formatDate(courseDate)}, ${getCourseTimeRange(course)}\n$trainer\nTipologia: ${course.tags.join(', ')}";
    } else {
      return "Orario: ${getCourseTimeRange(course)}\n$trainer\nTipologia: ${course.tags.join(', ')}";
    }
  }

  bool _canViewUserDetails() {
    return currentUser.role == 'Admin' || currentUser.role == 'Trainer';
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: getCourseUsers(course, _canViewUserDetails()),
      builder: (context, snapshot) {
        String iscritti = "";
        List<String> names = [];
        List<FitropeUser> users = [];
        List<FitropeUser> waitlistUsers = [];
        
        if (snapshot.connectionState == ConnectionState.waiting) {
          iscritti = "Iscritti: Caricamento iscritti...";
        } else if (snapshot.hasData) {
          names = snapshot.data!['subscribers']!.map((s) => s['displayName'] as String).toList();
          users = snapshot.data!['subscribers']!.map((s) => s['user'] as FitropeUser).toList();
          waitlistUsers = snapshot.data!['waitlistUsers']?.map((s) => s['user'] as FitropeUser).toList() ?? [];
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
              } else if (courseState == CourseState.CAN_WAITLIST) {
                onJoinWaitlist?.call();
              } else if (courseState == CourseState.IN_WAITLIST) {
                onLeaveWaitlist?.call();
              } else if (courseState == CourseState.WAITLIST_SPOT_AVAILABLE) {
                onSubscribe?.call();
              } else {
                onSubscribe?.call();
              }
            },
            capacity: course.capacity,
            subscribed: course.subscribed,
            subscribersNames: _canViewUserDetails() ? [] : names,
            subscribersUsers: _canViewUserDetails() ? users : null,
            waitlistUsers: _canViewUserDetails() ? waitlistUsers : null,
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