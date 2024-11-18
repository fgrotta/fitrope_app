import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/state.dart';

AppState appReducer(AppState state, dynamic action) {
  if (action is SetUserAction) {
    return AppState(user: action.user, isLoading: state.isLoading);
  }

  if (action is StartLoadingAction) {
    return AppState(user: state.user, isLoading: true);
  }

  if (action is FinishLoadingAction) {
    return AppState(user: state.user, isLoading: false);
  }
  
  return state;
}