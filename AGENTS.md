# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

FitRope (branded "Fit House") is a Flutter fitness class management app targeting Android, iOS, Web, and Windows. Backend is Firebase (Auth + Firestore) — no local backend server. See `DEPLOYMENT.md` for CI/CD and build commands.

### Flutter SDK

The project requires **Flutter >= 3.32.x** (Dart >= 3.8.0) based on the lockfile constraints. Flutter is installed at `/opt/flutter` and available on `PATH` via `~/.bashrc`.

### Case-sensitivity workaround (Linux)

`Protected.dart` imports `Homepage.dart` but the actual file is `HomePage.dart`. On Linux (case-sensitive FS) this breaks the build. A symlink `lib/pages/protected/Homepage.dart -> HomePage.dart` is needed. The update script creates it automatically.

### Running the app (web)

```bash
flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0
```

Then open `http://localhost:8080` in Chrome. The app loads a splash screen, then the Welcome page with "Entra" (Login) and "Registrati" (Register) buttons. Login/registration requires valid Firebase credentials for the `fit-rope-app-1f575` project.

### Key commands (per CI)

| Command | Purpose |
|---------|---------|
| `flutter pub get` | Install dependencies |
| `flutter test` | Run unit tests |
| `flutter analyze` | Static analysis / lint |
| `dart format --set-exit-if-changed .` | Format check |
| `flutter build web --debug` | Debug web build |

### Known pre-existing issues

- **Tests fail to compile**: test files don't pass the required `id` parameter to the `Course` constructor, and `Homepage.dart` import casing issue propagates into test compilation. These are repository-level bugs, not environment issues.
- **`flutter analyze` shows ~325 info-level warnings**: mostly `avoid_print`, `file_names`, and `prefer_const_constructors`. Also shows errors for the same missing `id` parameter in test files.
- **Format check fails on 67 files**: pre-existing formatting drift.
