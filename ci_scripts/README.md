# Xcode Cloud CI Scripts per Flutter

Questi script sono configurati per risolvere i problemi comuni di Xcode Cloud con Flutter.

## File creati:

- `ci_post_clone.sh` - Setup ambiente Flutter dopo il clone
- `ci_pre_xcodebuild.sh` - Pre-build: gestisce Generated.xcconfig e dipendenze
- `ci_post_xcodebuild.sh` - Post-build: test e verifiche
- `ci_scripts.sh` - Script principale

## Errori risolti:

1. **"could not find included file 'Generated.xcconfig'"**
   - Risolto creando Generated.xcconfig di fallback
   - Aggiornando Release.xcconfig e Debug.xcconfig con `#include?`

2. **"Unable to load contents of file list: Pods-Runner-frameworks"**
   - Risolto con `pod install --repo-update` nel pre-build script
   - Verifica esistenza file Pods

3. **File Pods mancanti**
   - Script verifica e reinstalla se necessario

## Configurazione in Xcode Cloud:

1. **Post-clone script:** `ci_scripts/ci_post_clone.sh`
2. **Pre-Xcode Build script:** `ci_scripts/ci_pre_xcodebuild.sh`
3. **Post-Xcode Build script:** `ci_scripts/ci_post_xcodebuild.sh`

## Environment Variables:

- `FLUTTER_ROOT=/usr/local/bin`
- `PATH=/usr/local/bin:$PATH`
- `FLUTTER_BUILD_MODE=release`

## Test locale:

```bash
# Testa gli script localmente
chmod +x ci_scripts/*.sh
./ci_scripts/ci_pre_xcodebuild.sh
```
