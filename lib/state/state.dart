import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';

class AppState {
  final bool isLoading;
  final FitropeUser? user;
  final List<Course> allCourses;

  AppState(
      {required this.user, required this.isLoading, required this.allCourses});

  AppState.initialState(this.isLoading, this.allCourses) : user = null;
}
