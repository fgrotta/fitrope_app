import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/state.dart';

AppState userReducer(AppState state, dynamic action) {
  if (action is SetUserAction) {
    return AppState(user: action.user);
  }
  
  return state;
}