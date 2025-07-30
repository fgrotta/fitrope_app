# FitRope App - Guida al Deployment

## Workflow CI/CD

Questo progetto utilizza GitHub Actions per automatizzare il processo di build e deployment.

### Branch e Workflow

#### Branch `main` e `develop`
- **Workflow**: `ci.yml`
- **Azioni**: Test, analisi del codice, controllo formattazione, build di test
- **Trigger**: Push e Pull Request

#### Branch `release`
- **Workflow**: `release.yml`
- **Azioni**: Test completi, build per tutte le piattaforme, creazione release automatica
- **Trigger**: Push e Pull Request

### Processo di Release

1. **Sviluppo**: Il codice viene sviluppato sui branch `main` o `develop`
2. **Test**: Ogni push attiva automaticamente i test CI
3. **Release**: Quando il codice è pronto per la produzione:
   - Merge su branch `release`
   - Build automatica per Android, iOS e Web
   - Creazione automatica di una GitHub Release
   - Upload dell'APK come asset della release
   - Deployment automatico su GitHub Pages

### Build Output

#### Android
- **File**: `app-release.apk`
- **Percorso**: `build/app/outputs/flutter-apk/app-release.apk`
- **Disponibile**: Come asset nelle GitHub Releases

#### iOS
- **File**: `Runner.app`
- **Percorso**: `build/ios/iphoneos/Runner.app`
- **Nota**: Build senza firma, richiede configurazione manuale per App Store

#### Web
- **Directory**: `build/web`
- **Contenuto**: File statici per deployment web
- **URL**: https://dellarosamarco.github.io/fitrope_app/
- **Deployment**: Automatico su GitHub Pages tramite branch `gh-pages`

### Configurazione Locale

Per eseguire build locali:

```bash
# Installazione dipendenze
flutter pub get

# Test
flutter test

# Analisi
flutter analyze

# Build Android
flutter build apk --release

# Build iOS
flutter build ios --release

# Build Web
flutter build web --release
```

### Dependabot

Il progetto utilizza Dependabot per:
- Aggiornamenti automatici delle dipendenze Dart/Flutter
- Aggiornamenti delle GitHub Actions
- Pull Request automatici ogni lunedì alle 9:00

### Troubleshooting

#### Build Fallite
1. Verificare che tutti i test passino localmente: `flutter test`
2. Controllare la formattazione del codice: `dart format .`
3. Verificare le dipendenze: `flutter pub deps`
4. Eseguire l'analisi del codice: `flutter analyze`

#### Problemi iOS
- Assicurarsi che Xcode sia aggiornato
- Verificare i certificati di sviluppo
- Controllare le configurazioni in `ios/Runner.xcodeproj`

#### Problemi Android
- Verificare che Android SDK sia configurato correttamente
- Controllare le configurazioni in `android/app/build.gradle`
- Verificare i file di firma in `android/app/`

### Contatti

Per problemi relativi al deployment, contattare il team di sviluppo. 