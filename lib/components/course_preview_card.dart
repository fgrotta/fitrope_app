import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/formatDate.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/utils/getCourseTimeRange.dart';
import 'package:fitrope_app/utils/user_display_utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CoursePreviewCard extends StatefulWidget {
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

  @override
  State<CoursePreviewCard> createState() => _CoursePreviewCardState();
}

class _CoursePreviewCardState extends State<CoursePreviewCard> {
  late Future<Map<String, List<Map<String, dynamic>>>> _courseUsersFuture;

  @override
  void initState() {
    super.initState();
    _courseUsersFuture = _getCourseUsers();
  }

  @override
  void didUpdateWidget(CoursePreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course.uid != widget.course.uid ||
        oldWidget.course.subscribed != widget.course.subscribed ||
        oldWidget.course.waitlist.length != widget.course.waitlist.length ||
        oldWidget.currentUser.uid != widget.currentUser.uid) {
      _courseUsersFuture = _getCourseUsers();
    }
  }

  bool _canViewUserDetails() {
    return widget.currentUser.role == 'Admin' || widget.currentUser.role == 'Trainer';
  }

  Future<Map<String, List<Map<String, dynamic>>>> _getCourseUsers() async {
    var usersCollection = FirebaseFirestore.instance.collection('users');

    var subscriberSnapshots = await usersCollection.where('courses', arrayContains: widget.course.uid).get();
    final subscribers = subscriberSnapshots.docs.map((doc) {
      final user = FitropeUser.fromJson(doc.data());
      return {
        'displayName': UserDisplayUtils.getDisplayName(user, _canViewUserDetails()),
        'user': user,
      };
    }).toList();

    List<Map<String, dynamic>> waitlistUsers = [];
    if (widget.course.waitlist.isNotEmpty && _canViewUserDetails()) {
      var waitlistSnapshots = await usersCollection.where('waitlistCourses', arrayContains: widget.course.uid).get();
      waitlistUsers = waitlistSnapshots.docs.map((doc) {
        final user = FitropeUser.fromJson(doc.data());
        return {
          'displayName': UserDisplayUtils.getDisplayName(user, true),
          'user': user,
        };
      }).toList();
    }

    return {'subscribers': subscribers, 'waitlistUsers': waitlistUsers};
  }

  String _buildDescription() {
    final trainer = "Trainer: ${UserDisplayUtils.getTrainerName(widget.course.trainerId, widget.trainers)}";

    if (widget.showDate) {
      final courseDate = DateTime.fromMillisecondsSinceEpoch(widget.course.startDate.millisecondsSinceEpoch);
      return "Orario: ${formatDate(courseDate)}, ${getCourseTimeRange(widget.course)}\n$trainer\nTipologia: ${widget.course.tags.join(', ')}";
    } else {
      return "Orario: ${getCourseTimeRange(widget.course)}\n$trainer\nTipologia: ${widget.course.tags.join(', ')}";
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: _courseUsersFuture,
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
        final courseState = getCourseState(widget.course, widget.currentUser);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: CourseCard(
            courseId: widget.course.uid,
            course: widget.course,
            title: widget.course.name,
            description: description,
            courseState: courseState,
            onClickAction: () {
              if (courseState == CourseState.SUBSCRIBED) {
                widget.onUnsubscribe?.call();
              } else if (courseState == CourseState.CAN_WAITLIST) {
                widget.onJoinWaitlist?.call();
              } else if (courseState == CourseState.IN_WAITLIST) {
                widget.onLeaveWaitlist?.call();
              } else if (courseState == CourseState.WAITLIST_SPOT_AVAILABLE) {
                widget.onSubscribe?.call();
              } else {
                widget.onSubscribe?.call();
              }
            },
            capacity: widget.course.capacity,
            subscribed: widget.course.subscribed,
            subscribersNames: _canViewUserDetails() ? [] : names,
            subscribersUsers: _canViewUserDetails() ? users : null,
            waitlistUsers: _canViewUserDetails() ? waitlistUsers : null,
            showClickableSubscribers: _canViewUserDetails(),
            isAdmin: widget.currentUser.role == 'Admin' || widget.currentUser.role == 'Trainer',
            userRole: widget.currentUser.role,
            onDuplicate: widget.onDuplicate,
            onDelete: widget.onDelete,
            onEdit: widget.onEdit,
            onRefresh: widget.onRefresh,
          ),
        );
      },
    );
  }
}
