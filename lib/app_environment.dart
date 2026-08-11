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
