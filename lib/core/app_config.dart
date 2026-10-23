/// Build-time flavor and endpoints, injected with `--dart-define`.
///
///   flutter build apk --dart-define=FLAVOR=prod \
///       --dart-define=API_BASE_URL=https://api.example.com \
///       --dart-define=TLS_PINS=<base64 sha256 of SPKI>,<backup pin>
enum Flavor { dev, staging, prod }

class AppConfig {
  AppConfig._();

  static const String _flavorName =
      String.fromEnvironment("FLAVOR", defaultValue: "dev");

  /// Base URL of the optional feed/API. Empty = the app makes no API calls.
  static const String apiBaseUrl =
      String.fromEnvironment("API_BASE_URL", defaultValue: "");

  /// Comma-separated base64 SHA-256 pins of the server's SPKI (include a backup).
  static const String _pinsCsv =
      String.fromEnvironment("TLS_PINS", defaultValue: "");

  static Flavor get flavor => Flavor.values.firstWhere(
        (f) => f.name == _flavorName,
        orElse: () => Flavor.dev,
      );

  static bool get isProd => flavor == Flavor.prod;

  static List<String> get tlsPins => _pinsCsv
      .split(",")
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
}
