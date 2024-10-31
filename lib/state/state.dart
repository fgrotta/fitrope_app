import 'package:fitrope_app/types/fitropeUser.dart';

class AppState {
  final FitropeUser? user;

  AppState({required this.user});

  AppState.initialState() : user=null;
}