import 'dart:async';

import 'package:fitrope_app/api/courses/get_attendance.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:fitrope_app/types/attendance_record.dart';
import 'package:fitrope_app/utils/attendance_window.dart';
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

  /// Check-in "Sono in sala" del socio; true se registrato.
  final Future<bool> Function()? onSelfCheckIn;

  /// Appello dello staff; true se il server ha registrato il valore.
  final Future<bool> Function(String userId, bool present)? onToggleAttendance;

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
    this.onSelfCheckIn,
    this.onToggleAttendance,
  });

  @override
  State<CoursePreviewCard> createState() => _CoursePreviewCardState();
}

class _CoursePreviewCardState extends State<CoursePreviewCard> {
  late Future<Map<String, List<Map<String, dynamic>>>> _courseUsersFuture;

  // ----- Presenze -----
  /// Appello (staff titolare): null finché la lista iscritti non viene aperta.
  Map<String, AttendanceRecord>? _attendance;

  /// Presenza del socio; letta solo da iscritto e a finestra self aperta.
  AttendanceRecord? _myAttendance;
  bool _myAttendanceRequested = false;
  final Set<String> _pendingAttendanceUids = {};

  /// Ricostruisce la card al prossimo confine delle finestre presenze.
  Timer? _boundaryTimer;

  @override
  void initState() {
    super.initState();
    _courseUsersFuture = _getCourseUsers();
    // Si aggancia al refresh globale (es. ripresa app) per rileggere
    // la lista iscritti dal server anche se le prop del corso non cambiano.
    RefreshManager().addListener(_refreshUsers);
    _scheduleAttendanceBoundary();
    _maybeLoadMyAttendance();
  }

  @override
  void dispose() {
    RefreshManager().removeListener(_refreshUsers);
    _boundaryTimer?.cancel();
    super.dispose();
  }

  void _refreshUsers() {
    if (!mounted) return;
    setState(() {
      _courseUsersFuture = _getCourseUsers();
    });
    if (_attendance != null) _loadCourseAttendance(force: true);
    if (_myAttendanceRequested) _maybeLoadMyAttendance(force: true);
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
    if (oldWidget.course.uid != widget.course.uid ||
        oldWidget.currentUser.uid != widget.currentUser.uid) {
      // Altro corso o altra identità (simulazione): niente stato ereditato.
      _attendance = null;
      _myAttendance = null;
      _myAttendanceRequested = false;
      _pendingAttendanceUids.clear();
    }
    if (oldWidget.course.startDate != widget.course.startDate ||
        oldWidget.course.uid != widget.course.uid) {
      _scheduleAttendanceBoundary();
    }
    _maybeLoadMyAttendance();
  }

  bool get _isStaff =>
      widget.currentUser.role == 'Admin' ||
      widget.currentUser.role == 'Trainer';

  /// Admin, o Trainer titolare (corso senza trainer compreso, come la UI di
  /// modifica e la callable).
  bool get _isOwnerStaff {
    final role = widget.currentUser.role;
    if (role == 'Admin') return true;
    if (role != 'Trainer') return false;
    final trainerId = widget.course.trainerId;
    return trainerId == null ||
        trainerId.isEmpty ||
        trainerId == widget.currentUser.uid;
  }

  bool get _isSubscribed =>
      widget.currentUser.courses.contains(widget.course.uid);

  bool _canMarkAttendance(DateTime now) =>
      _isStaff && _isOwnerStaff && staffCanMark(widget.course, now);

  void _scheduleAttendanceBoundary() {
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
    final now = DateTime.now();
    final next = nextAttendanceBoundary(widget.course, now);
    if (next == null) return;
    final delay = next.difference(now);
    // Solo i confini vicini: una card resta montata per ore, non per giorni.
    if (delay > const Duration(days: 1)) return;
    _boundaryTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {});
      _maybeLoadMyAttendance();
      _scheduleAttendanceBoundary();
    });
  }

  /// Zero letture sul calendario futuro: il doc del socio si legge solo se è
  /// iscritto e la finestra self è aperta o passata.
  void _maybeLoadMyAttendance({bool force = false}) {
    if (_isStaff || !_isSubscribed) return;
    if (_myAttendanceRequested && !force) return;
    final opensAt =
        widget.course.startDate.toDate().subtract(selfCheckInBefore);
    if (DateTime.now().isBefore(opensAt)) return;
    _myAttendanceRequested = true;
    final courseId = widget.course.uid;
    final uid = widget.currentUser.uid;
    getMyAttendance(courseId, uid, force: force).then((record) {
      if (!mounted ||
          widget.course.uid != courseId ||
          widget.currentUser.uid != uid) {
        return;
      }
      setState(() => _myAttendance = record);
    }).catchError((Object e) {
      debugPrint('getMyAttendance failed: $e');
    });
  }

  void _loadCourseAttendance({bool force = false}) {
    if (!_canMarkAttendance(DateTime.now())) return;
    final courseId = widget.course.uid;
    getCourseAttendance(courseId, force: force).then((records) {
      if (!mounted || widget.course.uid != courseId) return;
      setState(() => _attendance = records);
    }).catchError((Object e) {
      debugPrint('getCourseAttendance failed: $e');
    });
  }

  Future<bool> _selfCheckIn() async {
    final handler = widget.onSelfCheckIn;
    if (handler == null) return false;
    final ok = await handler();
    if (!mounted) return ok;
    if (ok) {
      setState(() {
        _myAttendance = AttendanceRecord(
          courseId: widget.course.uid,
          userId: widget.currentUser.uid,
          courseStartMillis: widget.course.startDate.millisecondsSinceEpoch,
          present: true,
          source: AttendanceSource.self,
          markedBy: widget.currentUser.uid,
        );
      });
    } else {
      // Rifiuto (es. lo staff aveva già registrato): riallinea col server.
      _maybeLoadMyAttendance(force: true);
    }
    return ok;
  }

  /// Flip alla risposta, non ottimistico: niente revert da gestire quando la
  /// guardia simulazione o le rules bloccano la richiesta.
  Future<void> _toggleAttendance(FitropeUser user, bool present) async {
    final handler = widget.onToggleAttendance;
    if (handler == null || _pendingAttendanceUids.contains(user.uid)) return;
    setState(() => _pendingAttendanceUids.add(user.uid));
    try {
      final ok = await handler(user.uid, present);
      if (!mounted || !ok) return;
      setState(() {
        _attendance = {
          ...?_attendance,
          user.uid: AttendanceRecord(
            courseId: widget.course.uid,
            userId: user.uid,
            courseStartMillis: widget.course.startDate.millisecondsSinceEpoch,
            present: present,
            source: widget.currentUser.role == 'Admin'
                ? AttendanceSource.admin
                : AttendanceSource.trainer,
            markedBy: widget.currentUser.uid,
          ),
        };
      });
    } finally {
      if (mounted) setState(() => _pendingAttendanceUids.remove(user.uid));
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
        final now = DateTime.now();
        final canMarkAttendance = _canMarkAttendance(now);
        // Il Trainer non titolare vede il conteggio, non i controlli.
        final showPresentCount = _isStaff && staffCanMark(widget.course, now);
        final checkInState = _isStaff
            ? null
            : selfCheckInState(
                widget.course,
                _myAttendance,
                now,
                isSubscribed: _isSubscribed,
              );

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
            selfCheckInState: checkInState,
            onSelfCheckIn: widget.onSelfCheckIn == null ? null : _selfCheckIn,
            canMarkAttendance: canMarkAttendance,
            showPresentCount: showPresentCount,
            attendanceRecords: canMarkAttendance ? _attendance : null,
            pendingAttendanceUids: _pendingAttendanceUids,
            onToggleAttendance:
                widget.onToggleAttendance == null ? null : _toggleAttendance,
            onSubscribersExpanded: _loadCourseAttendance,
          ),
        );
      },
    );
  }
}
