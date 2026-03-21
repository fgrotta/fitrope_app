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
- **Azioni**: Test completi, build web e creazione release automatica
- **Trigger**: Push e Pull Request

### Processo di Release

1. **Sviluppo**: Il codice viene sviluppato sui branch `main` o `develop`
2. **Test**: Ogni push attiva automaticamente i test CI
3. **Release**: Quando il codice è pronto per la produzione:
   - Merge su branch `release`
   - Build automatica web
   - Creazione automatica di una GitHub Release
   - Deployment automatico su GitHub Pages

### Build Output

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
1. Verificare che tutti i test passino localmente
2. Controllare la formattazione del codice: `flutter format .`
3. Verificare le dipendenze: `flutter pub deps`

### Contatti

Per problemi relativi al deployment, contattare il team di sviluppo. 
