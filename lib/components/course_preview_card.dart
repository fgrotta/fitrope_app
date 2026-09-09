import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/format_date.dart';
import 'package:fitrope_app/utils/get_course_state.dart';
import 'package:fitrope_app/utils/get_course_time_range.dart';
import 'package:fitrope_app/utils/italian_time.dart';
import 'package:fitrope_app/utils/user_display_utils.dart';
import 'package:fitrope_app/utils/refresh_manager.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CoursePreviewCard extends StatefulWidget {
  final Course course;
  final FitropeUser currentUser;
  final List<FitropeUser> trainers;
  final Future<void> Function()? onSubscribe;
  final Future<void> Function()? onUnsubscribe;
  final Future<void> Function()? onJoinWaitlist;
  final Future<void> Function()? onLeaveWaitlist;
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
    // Si aggancia al refresh globale (es. ripresa app) per rileggere
    // la lista iscritti dal server anche se le prop del corso non cambiano.
    RefreshManager().addListener(_refreshUsers);
  }

  @override
  void dispose() {
    RefreshManager().removeListener(_refreshUsers);
    super.dispose();
  }

  void _refreshUsers() {
    if (!mounted) return;
    setState(() {
      _courseUsersFuture = _getCourseUsers();
    });
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
    return widget.currentUser.role == 'Admin' ||
        widget.currentUser.role == 'Trainer';
  }

  Future<Map<String, List<Map<String, dynamic>>>> _getCourseUsers() async {
    var usersCollection = FirebaseFirestore.instance.collection('users');

    var subscriberSnapshots = await usersCollection
        .where('courses', arrayContains: widget.course.uid)
        .get();
    final subscribers = subscriberSnapshots.docs.map((doc) {
      final user = FitropeUser.fromJson(doc.data());
      return {
        'displayName':
            UserDisplayUtils.getDisplayName(user, _canViewUserDetails()),
        'user': user,
      };
    }).toList();

    List<Map<String, dynamic>> waitlistUsers = [];
    if (widget.course.waitlist.isNotEmpty && _canViewUserDetails()) {
      var waitlistSnapshots = await usersCollection
          .where('waitlistCourses', arrayContains: widget.course.uid)
          .get();
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
    final trainer =
        "Trainer: ${UserDisplayUtils.getTrainerName(widget.course.trainerId, widget.trainers)}";

    // La tipologia non è più una riga di metadati: sta nel badge colorato in
    // testa alla card, che mostra la tipologia REALE (dai `tags`) e non l'enum
    // legacy `courseType`, che conosce solo Open e Personal Trainer.
    // Al suo posto la sala, che finora era salvata ma non mostrata da nessuna
    // parte in lettura.
    final sala = "Sala: ${widget.course.sala ?? 'Nessuna sala'}";

    if (widget.showDate) {
      final courseDate = toItalianTime(widget.course.startDate.toDate());
      return "Orario: ${formatDate(courseDate)}, ${getCourseTimeRange(widget.course)}\n$trainer\n$sala";
    } else {
      return "Orario: ${getCourseTimeRange(widget.course)}\n$trainer\n$sala";
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: _courseUsersFuture,
      builder: (context, snapshot) {
        List<String> names = [];
        List<FitropeUser> users = [];
        List<FitropeUser> waitlistUsers = [];

        if (snapshot.hasData) {
          names = snapshot.data!['subscribers']!
              .map((s) => s['displayName'] as String)
              .toList();
          users = snapshot.data!['subscribers']!
              .map((s) => s['user'] as FitropeUser)
              .toList();
          waitlistUsers = snapshot.data!['waitlistUsers']
                  ?.map((s) => s['user'] as FitropeUser)
                  .toList() ??
              [];
        }

        // La lista iscritti non compare nei metadati: il conteggio è già nella
        // pill in alto, i nomi nel dialog "Vedi iscritti" (utente) o nel box
        // dedicato (admin/trainer). Evita così il "salto" di altezza della card
        // quando termina il caricamento degli iscritti (riga transitoria che
        // appariva e poi spariva a ogni cambio giorno).
        final description = _buildDescription();
        final courseState = getCourseState(widget.course, widget.currentUser);

        return Container(
          key: Key('course-card-${widget.course.uid}'),
          margin: const EdgeInsets.only(bottom: 10),
          child: CourseCard(
            courseId: widget.course.uid,
            course: widget.course,
            title: widget.course.name,
            description: description,
            courseState: courseState,
            onClickAction: () async {
              if (courseState == CourseState.SUBSCRIBED) {
                await widget.onUnsubscribe?.call();
              } else if (courseState == CourseState.CAN_WAITLIST) {
                await widget.onJoinWaitlist?.call();
              } else if (courseState == CourseState.IN_WAITLIST) {
                await widget.onLeaveWaitlist?.call();
              } else if (courseState == CourseState.WAITLIST_SPOT_AVAILABLE) {
                await widget.onSubscribe?.call();
              } else {
                await widget.onSubscribe?.call();
              }
            },
            capacity: widget.course.capacity,
            subscribed: widget.course.subscribed,
            subscribersNames: _canViewUserDetails() ? [] : names,
            subscribersUsers: _canViewUserDetails() ? users : null,
            waitlistUsers: _canViewUserDetails() ? waitlistUsers : null,
            showClickableSubscribers: _canViewUserDetails(),
            isAdmin: widget.currentUser.role == 'Admin' ||
                widget.currentUser.role == 'Trainer',
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
