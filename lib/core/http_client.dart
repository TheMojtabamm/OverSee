import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:crypto/crypto.dart" show sha256;
import "package:dio/dio.dart";
import "package:dio/io.dart";

import "app_config.dart";

/// Extracts the SubjectPublicKeyInfo (SPKI) bytes from a DER X.509 certificate.
/// Pinning the SPKI (not the whole certificate) survives routine certificate
/// renewal as long as the key pair is reused, and lets us pin a backup key.
Uint8List extractSpki(Uint8List der) {
  // Certificate ::= SEQUENCE { tbsCertificate SEQUENCE { [0] version OPTIONAL,
  //   serial, signatureAlg, issuer, validity, subject, subjectPublicKeyInfo, … } }
  final cert = _Tlv.read(der, 0);
  final tbs = _Tlv.read(der, cert.valueStart);
  var pos = tbs.valueStart;
  final t = _Tlv.read(der, pos);
  if (t.tag == 0xA0) {
    // explicit version
    pos = t.end;
  }
  // serial, signatureAlg, issuer, validity, subject
  for (var i = 0; i < 5; i++) {
    pos = _Tlv.read(der, pos).end;
  }
  final spki = _Tlv.read(der, pos);
  return Uint8List.sublistView(der, spki.start, spki.end);
}

String spkiPin(Uint8List der) =>
    base64.encode(sha256.convert(extractSpki(der)).bytes);

class _Tlv {
  final int tag;
  final int start;
  final int valueStart;
  final int end;
  const _Tlv(this.tag, this.start, this.valueStart, this.end);

  static _Tlv read(Uint8List b, int start) {
    final tag = b[start];
    var p = start + 1;
    var len = b[p++];
    if (len & 0x80 != 0) {
      final n = len & 0x7F;
      len = 0;
      for (var i = 0; i < n; i++) {
        len = (len << 8) | b[p++];
      }
    }
    return _Tlv(tag, start, p, p + len);
  }
}

/// Builds the app's HTTP client: sane timeouts, SPKI pinning, and a small
/// bounded retry for idempotent GETs.
///
/// In prod a base URL without pins is refused (fail closed).
Dio buildHttpClient({String? baseUrl, List<String>? pins, bool? prod}) {
  final url = baseUrl ?? AppConfig.apiBaseUrl;
  final pinSet = (pins ?? AppConfig.tlsPins).toSet();
  if ((prod ?? AppConfig.isProd) && url.isNotEmpty && pinSet.isEmpty) {
    throw StateError("Refusing to build a prod HTTP client without TLS pins.");
  }

  final dio = Dio(BaseOptions(
    baseUrl: url,
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));

  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () =>
        HttpClient()..badCertificateCallback = (_, __, ___) => false,
    validateCertificate: (cert, host, port) {
      if (pinSet.isEmpty) return true; // dev/staging without pins
      if (cert == null) return false;
      try {
        return pinSet.contains(spkiPin(cert.der));
      } catch (_) {
        return false;
      }
    },
  );

  dio.interceptors.add(_RetryInterceptor(dio));
  return dio;
}

class _RetryInterceptor extends Interceptor {
  final Dio _dio;
  static const _max = 2;
  _RetryInterceptor(this._dio);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    final tries = (req.extra["retry"] as int?) ?? 0;
    final retryable = req.method == "GET" &&
        tries < _max &&
        (err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.receiveTimeout ||
            err.type == DioExceptionType.connectionError ||
            (err.response?.statusCode ?? 0) >= 500);
    if (!retryable) return handler.next(err);

    await Future<void>.delayed(Duration(milliseconds: 400 * (1 << tries)));
    req.extra["retry"] = tries + 1;
    try {
      handler.resolve(await _dio.fetch<dynamic>(req));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
