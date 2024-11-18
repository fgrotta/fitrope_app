import 'package:fitrope_app/types/fitropeUser.dart';

class AppState {
  final bool isLoading;
  final FitropeUser? user;

  AppState({required this.user, required this.isLoading});

  AppState.initialState(this.isLoading) : user=null;
}