import "dart:async";
import "dart:convert";
import "dart:io";

/// Why a fetch failed, in words that are safe to show (never the URL or the body).
class SubscriptionFetchException implements Exception {
  final String message;
  const SubscriptionFetchException(this.message);
  @override
  String toString() => message;
}

typedef SubscriptionFetcher = Future<String> Function(Uri url);

/// Downloads a subscription body. The app is excluded from its own VPN, so this goes out over
/// the phone's normal network (which is what you want when the tunnel is not up yet).
class SubscriptionService {
  static const maxBytes = 2 * 1024 * 1024;
  final SubscriptionFetcher fetch;
  SubscriptionService({SubscriptionFetcher? fetcher})
      : fetch = fetcher ?? _http;

  static Future<String> _http(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = "Oversea";
    try {
      final req = await client.getUrl(url).timeout(const Duration(seconds: 15));
      req.followRedirects = true;
      req.maxRedirects = 4;
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw SubscriptionFetchException(
            "The server answered ${res.statusCode}");
      }
      final bytes = <int>[];
      await for (final chunk in res.timeout(const Duration(seconds: 25))) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          throw const SubscriptionFetchException("The list is too large");
        }
      }
      return utf8.decode(bytes, allowMalformed: true);
    } on SubscriptionFetchException {
      rethrow;
    } on TimeoutException {
      throw const SubscriptionFetchException("The server took too long");
    } on HandshakeException {
      throw const SubscriptionFetchException(
          "Secure connection failed (certificate problem)");
    } on SocketException {
      throw const SubscriptionFetchException(
          "Could not reach the server. Check your internet connection");
    } on HttpException {
      throw const SubscriptionFetchException("The server sent a bad answer");
    } finally {
      client.close(force: true);
    }
  }
}
