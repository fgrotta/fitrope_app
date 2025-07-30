import 'package:fitrope_app/state/reducers.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:redux/redux.dart';
import 'package:redux_thunk/redux_thunk.dart';

final store = Store<AppState>(
  appReducer,
  initialState: AppState.initialState(false, []),
  middleware: [thunkMiddleware],
);
