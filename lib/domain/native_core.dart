import "dart:ffi";
import "dart:io";
import "dart:typed_data";

import "package:ffi/ffi.dart";

/// Binding to libovs.so (android/app/src/main/cpp): the lock key derivation and gate
/// MAC computed in native code, so the secret parts, the mask and the stretch are not
/// in the Dart snapshot. Null when the library isn't present (tests, desktop, dev
/// builds without the NDK) — callers then use the Dart implementation.
class NativeCore {
  final int Function() _caps;
  final int Function(int, Pointer<Uint8>, int, Pointer<Utf8>, Pointer<Uint8>)
      _derive;
  final int Function(
      Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Utf8>, Pointer<Utf8>) _mac;

  NativeCore._(this._caps, this._derive, this._mac);

  static NativeCore? _cached;
  static bool _tried = false;

  /// The shared instance, or null if the native library can't be loaded.
  static NativeCore? get instance {
    if (_tried) return _cached;
    _tried = true;
    _cached = _load();
    return _cached;
  }

  /// Test hook: forget the cached instance.
  static void resetForTest() {
    _tried = false;
    _cached = null;
  }

  static NativeCore? _load() {
    try {
      final path = Platform
          .environment["OVS_NATIVE_LIB"]; // tests point this at a host build
      final lib = path != null && path.isNotEmpty
          ? DynamicLibrary.open(path)
          : (Platform.isAndroid ? DynamicLibrary.open("libovs.so") : null);
      if (lib == null) return null;
      return NativeCore._(
        lib.lookupFunction<Int32 Function(), int Function()>(
            "ovs_capabilities"),
        lib.lookupFunction<
            Int32 Function(
                Int32, Pointer<Uint8>, Int32, Pointer<Utf8>, Pointer<Uint8>),
            int Function(int, Pointer<Uint8>, int, Pointer<Utf8>,
                Pointer<Uint8>)>("ovs_derive_file_key"),
        lib.lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int64, Pointer<Utf8>,
                Pointer<Utf8>),
            int Function(Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Utf8>,
                Pointer<Utf8>)>("ovs_gate_mac"),
      );
    } catch (_) {
      return null;
    }
  }

  bool get hasLockKey => _caps() & 1 != 0;
  bool get hasGateKey => _caps() & 2 != 0;

  /// 32-byte AES key for a file with [salt], or null if the lock key isn't configured.
  Uint8List? deriveFileKey(int keyGeneration, List<int> salt, String envTag) {
    final s = calloc<Uint8>(salt.length);
    final out = calloc<Uint8>(32);
    final tag = envTag.toNativeUtf8();
    try {
      s.asTypedList(salt.length).setAll(0, salt);
      if (_derive(keyGeneration, s, salt.length, tag, out) != 0) return null;
      return Uint8List.fromList(out.asTypedList(32));
    } finally {
      calloc.free(s);
      calloc.free(out);
      calloc.free(tag);
    }
  }

  /// hex(HMAC(appKey[|env], "ovsea-gate-v2|code|fp|day")), or null if no gate key.
  String? gateMac(String code, String creatorFp, int day, String envTag) {
    final c = code.toNativeUtf8();
    final f = creatorFp.toNativeUtf8();
    final t = envTag.toNativeUtf8();
    final out = calloc<Uint8>(65).cast<Utf8>();
    try {
      if (_mac(c, f, day, t, out) != 0) return null;
      return out.toDartString();
    } finally {
      calloc.free(c);
      calloc.free(f);
      calloc.free(t);
      calloc.free(out);
    }
  }
}
