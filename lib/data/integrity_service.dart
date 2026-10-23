import "package:flutter/services.dart";

import "../domain/locked_config_codec.dart";
import "../domain/tamper.dart";

/// Reads the native integrity signals once at startup and tells the lock codec and
/// the gate token what environment they are running in.
class IntegrityService {
  static const _m = MethodChannel("oversea/tunnel");

  static Future<void> init() async {
    try {
      final r = await _m.invokeMapMethod<String, Object?>("integrity");
      final tag = Tamper.environmentTag(
        cert: r?["cert"] as String?,
        flags: (r?["flags"] as num?)?.toInt() ?? 0,
      );
      LockedConfigCodec.environmentTag = tag;
    } on MissingPluginException {
      // no native side (tests / desktop): behave as a clean environment
    } catch (_) {
      // never block startup on this
    }
  }
}
