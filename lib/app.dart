import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "core/strings.dart";
import "features/shell/root_shell.dart";
import "providers.dart";

const accent = Color(0xFF38E1D4);

class OverseaApp extends ConsumerWidget {
  const OverseaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      title: "Oversea",
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: ThemeMode.system,
      theme: ThemeData(colorSchemeSeed: accent, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: accent,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const RootShell(),
    );
  }
}
