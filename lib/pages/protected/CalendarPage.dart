import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/api/courses/subscribeToCourse.dart';
import 'package:fitrope_app/api/courses/deleteCourse.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/utils/waitlist_ui_helper.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/components/course_preview_card.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/utils/course_unsubscribe_helper.dart';
import 'package:fitrope_app/utils/regolamento_helper.dart';
import 'package:fitrope_app/components/loader.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/course_type.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/router.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/components/calendar.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:intl/intl.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime firstDate = DateTime(DateTime.now().year - 1, 1, 1);
  DateTime lastDate = DateTime(DateTime.now().year + 1, 12, 31);
  List<Course> courses = [];
  List<FitropeUser> trainers = [];
  Map<String, List<Course>> coursesByDate = {};
  List<Course> selectedCourses = [];
  late FitropeUser user;
  late DateTime currentDate;
  var pattern = "yyyy-MM-dd";
  final defaultTimeOfDay = const TimeOfDay(hour: 19, minute: 0);
  String? _tagFilter; // null = tutti i tag

  @override
  void initState() {
    currentDate = DateTime.now();
    user = store.state.user!;
    getTrainers().then((List<FitropeUser> response) {
      setState(() {
        trainers = response;
      });
    });
    getAllCourses().then((List<Course> response) {
      setState(() {
        refreshCourseMap(response);
        onSelectDate(DateTime.now());
      });
    });
    super.initState();
  }

  void refreshCourseMap(List<Course> response) {
    coursesByDate.clear();
    store.dispatch(SetAllCoursesAction(response));    
    courses = response;
    for(Course course in response) {
      updateCourseToMap(course, null);
    }
    
  }

  void updateCourseToMap(Course newCourse, Course? oldCourse ) {
    if (oldCourse != null) {
      removeCoruseFromMap(oldCourse);
    }
    DateTime courseDate = DateTime.fromMillisecondsSinceEpoch(newCourse.startDate.millisecondsSinceEpoch);
    String indexDate = DateFormat(pattern).format(courseDate);
    if(!coursesByDate.containsKey(indexDate)) {
      coursesByDate[indexDate] = [];
    }
    coursesByDate[indexDate]!.add(newCourse);
  }

  void removeCoruseFromMap(Course oldCourse) {
    coursesByDate[DateFormat(pattern).format(oldCourse.startDate.toDate())]!.remove(oldCourse);
  }

  void updateCourses() {
    invalidateUsersCache();
    user = store.state.user!;
    invalidateCoursesCache();
    selectedCourses = [];
    getAllCourses().then((List<Course> response) {
      if(mounted) { 
        refreshCourseMap(response);
        onSelectDate(currentDate);
        store.dispatch(SetAllCoursesAction(response));
      }
    });
  }

  void onSelectDate(DateTime selectedDate) {
    currentDate = selectedDate;
    _tagFilter = null; // ogni giorno riparte da "Tutti"
    selectedCourses = [];
    String indexDate = DateFormat(pattern).format(selectedDate);
    if (coursesByDate[indexDate]!=null){
      selectedCourses = coursesByDate[indexDate]!;
    } 

    setState(() { });
  }

  void onSubscribe(Course course) async {
    bool accepted = await RegolamentoHelper.checkAndAcceptRegolamento(context, user);
    if (!accepted) return;

    subscribeToCourse(course.id, user.uid).then((_) {
      setState(() {
        updateCourses();
      });
    });
  }

  void onUnsubscribe(Course course) async {
    try {
      print('🔄 Inizio disiscrizione per corso: ${course.name}');
      
      // Usa il nuovo sistema di disiscrizione intelligente
      bool success = await CourseUnsubscribeHelper.handleUnsubscribe(
        course,
        user,
        context,
      );
      
      if (success) {
        print('✅ Disiscrizione completata con successo');
        
        // Aggiorna lo stato dell'utente corrente
        if (store.state.user != null && store.state.user!.uid == user.uid) {
          // Ricarica i dati utente per aggiornare entrateDisponibili e courses
          try {
            print('🔄 Aggiornamento stato utente nello store');
            final userData = await getUserData(user.uid);
            if (userData != null) {
              store.dispatch(SetUserAction(FitropeUser.fromJson(userData)));
            }
          } catch (e) {
            print('⚠️ Errore nell\'aggiornamento stato utente: $e');
          }
        }
        updateCourses();
        // Mostra messaggio di successo
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Disiscrizione completata con successo'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('❌ Disiscrizione annullata dall\'utente');
        // L'utente ha annullato la disiscrizione, non fare nulla
      }
      
    } catch (e) {
      print('❌ Errore durante la disiscrizione: $e');
      SnackBarUtils.showErrorSnackBar(
        context,
        'Errore durante la disiscrizione: ${e.toString()}',
      );
    }
  }

  void onJoinWaitlist(Course course) {
    WaitlistUiHelper.showJoinWaitlistDialog(
      context: context,
      course: course,
      userId: user.uid,
      onRefresh: updateCourses,
      isMounted: () => mounted,
    );
  }

  void onLeaveWaitlist(Course course) {
    WaitlistUiHelper.handleLeaveWaitlist(
      context: context,
      course: course,
      userId: user.uid,
      onRefresh: updateCourses,
      isMounted: () => mounted,
    );
  }

  // Funzioni per navigare alla pagina di gestione corsi
  void showCreateCoursePage() {
    Navigator.pushNamed(
      context,
      COURSE_MANAGEMENT_ROUTE,
      arguments: {
        'mode': 'create',
      },
    ).then((result) {
      if (result == true) {
        updateCourses();
      }
    });
  }

  void showDuplicateCoursePage(Course originalCourse) {
    Navigator.pushNamed(
      context,
      COURSE_MANAGEMENT_ROUTE,
      arguments: {
        'mode': 'duplicate',
        'courseToDuplicate': originalCourse,
      },
    ).then((result) {
      if (result == true) {
        updateCourses();
      }
    });
  }

  void showEditCoursPage(Course course) {
    Navigator.pushNamed(
      context,
      COURSE_MANAGEMENT_ROUTE,
      arguments: {
        'mode': 'edit',
        'courseToEdit': course,
      },
    ).then((result) {
      if (result == true) {
        updateCourses();
      }
    });
  }
  
  void showRecurringCoursePage() {
    Navigator.pushNamed(
      context,
      RECURRING_COURSE_ROUTE,
    ).then((result) {
      if (result == true) {
        updateCourses();
      }
    });
  }
  // Funzione di utilità per verificare se un corso è nel futuro
  bool _isCourseInFuture(Course course) {
    return course.startDate.toDate().isAfter(DateTime.now());
  }

  void deleteCourseAndUpdate(Course course) async {
    try {
      await deleteCourse(course.uid);
      updateCourses();
      
      // Mostra SnackBar di successo
      SnackBarUtils.showSuccessSnackBar(
        context,
        'Corso cancellato con successo',
      );
    } catch (e) {
      // Mostra SnackBar di errore
      SnackBarUtils.showErrorSnackBar(
        context,
        'Errore durante la cancellazione del corso',
      );
    }
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Image(image: AssetImage('assets/new_logo_only.png'), width: 30),
        Expanded(
          child: Text(
            'Calendario corsi',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 26,
              color: onPrimaryColor,
            ),
          ),
        ),
        if (isDesktop(context))
          const SizedBox(width: 30)
        else
          GestureDetector(
            child: CircleAvatar(
              backgroundColor: const Color.fromARGB(255, 96, 119, 246),
              child: Text(user.name[0] + user.lastName[0]),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UserDetailPage(user: user)),
              );
            },
          ),
      ],
    );
  }

  Widget _buildCalendar() {
    return Theme(
      data: ThemeData(
        colorScheme: const ColorScheme.highContrastDark(onSurface: onPrimaryColor),
        datePickerTheme: DatePickerThemeData(
          dayForegroundColor: WidgetStateProperty.all(onSurfaceColor),
          weekdayStyle: const TextStyle(color: onPrimaryColor),
          headerHeadlineStyle: const TextStyle(color: onPrimaryColor),
          todayForegroundColor: WidgetStateProperty.all(onPrimaryColor),
          todayBackgroundColor: WidgetStateProperty.all(onSurfaceVariantColorTrasparent),
          yearOverlayColor: WidgetStateProperty.all(surfaceVariantColor),
          yearBackgroundColor: WidgetStateProperty.all(primaryLightColor),
          yearForegroundColor: WidgetStateProperty.all(onPrimaryColor),
          dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return primaryLightColor;
            }
            return null;
          }),
        ),
      ),
      child: Calendar(
        onDateChanged: (DateTime value) {
          onSelectDate(value);
        },
        initialDate: DateTime.now(),
        firstDate: firstDate,
        lastDate: lastDate,
        filledDays: courses.map((Course course) => course.startDate.toDate()).toList(),
      ),
    );
  }

  Widget _buildSectionHeader(CourseType type) {
    IconData icon;
    Color accentColor;
    switch (type) {
      case CourseType.personal_trainer:
        icon = Icons.person;
        accentColor = primaryColor;
        break;
      case CourseType.open:
        icon = Icons.group;
        accentColor = secondaryColor;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: accentColor, size: 20),
          const SizedBox(width: 8),
          Text(
            type.label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: accentColor.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseCard(Course course) {
    return CoursePreviewCard(
      key: ValueKey(course.uid),
      course: course,
      currentUser: user,
      trainers: trainers,
      showDate: false,
      onSubscribe: () => onSubscribe(course),
      onUnsubscribe: () => onUnsubscribe(course),
      onJoinWaitlist: () => onJoinWaitlist(course),
      onLeaveWaitlist: () => onLeaveWaitlist(course),
      onDuplicate: () => showDuplicateCoursePage(course),
      onDelete: user.role == 'Admin' ? () => deleteCourseAndUpdate(course) : null,
      onEdit: (user.role == 'Admin' ||
              (user.role == 'Trainer' &&
                  (course.trainerId == null || course.trainerId == user.uid)))
          ? (_isCourseInFuture(course) ? () => showEditCoursPage(course) : null)
          : null,
      onRefresh: () => updateCourses(),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  // Intestazione di contesto: giorno selezionato + numero di corsi.
  Widget _buildDayContextHeader() {
    final label = _capitalize(DateFormat('EEEE d MMMM', 'it_IT').format(currentDate));
    final n = selectedCourses.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: onPrimaryColor)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: primaryLightColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$n cors${n == 1 ? 'o' : 'i'}',
                style: const TextStyle(
                    color: primaryColor, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: onPrimaryColor.withValues(alpha: 0.30)),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: onPrimaryColor.withValues(alpha: 0.65), fontSize: 15)),
          ],
        ),
      ),
    );
  }

  // Chip di filtro per tag dei corsi del giorno selezionato. I tag sono
  // dinamici: i chip mostrano "Tutti" + i tag effettivamente presenti.
  Widget _buildTagFilterChips() {
    if (selectedCourses.isEmpty) return const SizedBox.shrink();
    final tags = selectedCourses.expand((c) => c.tags).toSet().toList()..sort();
    if (tags.isEmpty) return const SizedBox.shrink();

    int countOf(String? tag) => tag == null
        ? selectedCourses.length
        : selectedCourses.where((c) => c.tags.contains(tag)).length;
    Widget chip(String label, String? value) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text('$label (${countOf(value)})'),
            selected: _tagFilter == value,
            onSelected: (_) => setState(() => _tagFilter = value),
            visualDensity: VisualDensity.compact,
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.filter_list,
                    size: 16, color: onPrimaryColor.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text('Filtra per tag',
                    style: TextStyle(
                        fontSize: 12,
                        color: onPrimaryColor.withValues(alpha: 0.6))),
              ],
            ),
          ),
          Wrap(
            spacing: 0,
            runSpacing: 4,
            children: [
              chip('Tutti', null),
              ...tags.map((t) => chip(t, t)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedCoursesList() {
    if (selectedCourses.isEmpty) {
      return _buildEmptyState(
          Icons.event_busy, 'Nessun corso programmato in questa giornata');
    }

    // Applica il filtro per tag (chip).
    final visible = _tagFilter == null
        ? selectedCourses
        : selectedCourses.where((c) => c.tags.contains(_tagFilter)).toList();
    if (visible.isEmpty) {
      return _buildEmptyState(
          Icons.filter_alt_off, 'Nessun corso con il tag "$_tagFilter" in questa giornata');
    }

    // Raggruppa i corsi per tipologia
    final groupedCourses = <CourseType, List<Course>>{};
    for (final course in visible) {
      groupedCourses.putIfAbsent(course.courseType, () => []);
      groupedCourses[course.courseType]!.add(course);
    }

    // Ordine di visualizzazione delle sezioni
    const typeOrder = [CourseType.personal_trainer, CourseType.open];

    // Se c'è un solo tipo, mostra senza header di sezione
    final presentTypes = typeOrder.where((type) => groupedCourses.containsKey(type)).toList();
    if (presentTypes.length <= 1) {
      return Column(
        children: visible.map((course) => _buildCourseCard(course)).toList(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: presentTypes.expand((type) => [
        _buildSectionHeader(type),
        ...groupedCourses[type]!.map((course) => _buildCourseCard(course)),
      ]).toList(),
    );
  }

  Widget _buildActionButtons({required bool compact}) {
    if (user.role != 'Admin' && user.role != 'Trainer') {
      return const SizedBox.shrink();
    }

    if (compact) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: showCreateCoursePage,
              icon: const Icon(Icons.add, color: onPrimaryColor),
              label: const Text('Crea nuovo corso', style: TextStyle(color: onPrimaryColor)),
              style: ElevatedButton.styleFrom(backgroundColor: surfaceVariantColor),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: showRecurringCoursePage,
              icon: const Icon(Icons.repeat, color: onPrimaryColor),
              label: const Text('Corsi ricorrenti', style: TextStyle(color: onPrimaryColor)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: showCreateCoursePage,
            icon: const Icon(Icons.add, color: onPrimaryColor),
            label: const Text('Crea nuovo corso', style: TextStyle(color: onPrimaryColor)),
            style: ElevatedButton.styleFrom(backgroundColor: surfaceVariantColor),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: showRecurringCoursePage,
            icon: const Icon(Icons.repeat, color: onPrimaryColor),
            label: const Text('Corsi ricorrenti', style: TextStyle(color: onPrimaryColor)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenType = breakpointOf(context);
    final bool isDesktopLayout = screenType == ScreenType.desktop || screenType == ScreenType.largeDesktop;

    return StoreConnector<AppState, AppState>(
      converter: (store) => store.state,
      builder: (context, state) {
        return Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding, top: pagePadding + MediaQuery.of(context).viewPadding.top),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  if (isDesktopLayout)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCalendar(),
                              const SizedBox(height: 16),
                              _buildActionButtons(compact: false),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 7,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDayContextHeader(),
                                _buildTagFilterChips(),
                                _buildSelectedCoursesList(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _buildCalendar(),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDayContextHeader(),
                          _buildTagFilterChips(),
                          _buildSelectedCoursesList(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding),
                      child: _buildActionButtons(compact: true),
                    ),
                  ],
                ],
              )),
            if (state.isLoading) const Loader(),
          ],
        );
      }
    );
  }
}