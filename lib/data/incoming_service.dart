import "dart:async";

import "package:flutter/services.dart";

/// Text/file another app shared with Oversea ("Open with" / Share). Delivered once.
class IncomingService {
  static const _m = MethodChannel("oversea/incoming");

  /// Calls [onText] for the file the app was launched with and for later ones.
  static void listen(void Function(String text) onText) {
    Future<void> pull() async {
      try {
        final t = await _m.invokeMethod<String>("take");
        if (t != null && t.isNotEmpty) onText(t);
      } on MissingPluginException {
        // no native side
      } catch (_) {}
    }

    _m.setMethodCallHandler((call) async {
      if (call.method == "onIncoming") await pull();
    });
    pull(); // launched by a file
  }
}
