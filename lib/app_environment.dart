import 'package:flutter/foundation.dart';

enum AppEnvironment {
  prod,
  staging,
}

const String _environmentName =
    String.fromEnvironment("APP_ENV", defaultValue: "prod");

const AppEnvironment appEnvironment = _environmentName == "staging"
    ? AppEnvironment.staging
    : AppEnvironment.prod;

const bool isStaging = appEnvironment == AppEnvironment.staging;

/// Strumenti di debug (pagina `DebugEmailPage`, route `/debug-email`): in debug
/// locale e sulla build staging, mai in produzione. È `const`, quindi nella
/// build di produzione la libreria differita della pagina resta fuori dal bundle.
const bool debugToolsEnabled = kDebugMode || isStaging;
