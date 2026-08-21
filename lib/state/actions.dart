import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';

class SetUserAction {
  final FitropeUser? user;

  SetUserAction(this.user);
}

class StartLoadingAction {
  StartLoadingAction();
}

class FinishLoadingAction {
  FinishLoadingAction();
}

class SetAllCoursesAction {
  final List<Course> courses;

  SetAllCoursesAction(this.courses);
}

/// Ripristina lo stato globale tra scenari E2E eseguiti nello stesso processo.
class ResetAppStateAction {
  const ResetAppStateAction();
}
