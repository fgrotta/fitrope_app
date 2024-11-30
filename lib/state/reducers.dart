import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/state.dart';

AppState appReducer(AppState state, dynamic action) {
  if (action is SetUserAction) {
    return AppState(user: action.user, isLoading: state.isLoading, allCourses: state.allCourses);
  }

  if (action is StartLoadingAction) {
    return AppState(user: state.user, isLoading: true, allCourses: state.allCourses);
  }

  if (action is FinishLoadingAction) {
    return AppState(user: state.user, isLoading: false, allCourses: state.allCourses);
  }

  if (action is SetAllCoursesAction) {
    return AppState(user: state.user, isLoading: state.isLoading, allCourses: action.courses);
  }
  
  return state;
}