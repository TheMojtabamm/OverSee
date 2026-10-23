import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "app.dart";
import "data/ad_service.dart";
import "data/integrity_service.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await IntegrityService
      .init(); // sets the environment tag before anything is opened
  // Ads must never block startup; failures are swallowed.
  unawaited(AdService.init().catchError((_) {}));
  runApp(const ProviderScope(child: OverseaApp()));
}
