import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dashboard_skin.dart';
import 'desktop_window.dart';
import 'scheduler_home.dart';

class SchedulerApp extends StatelessWidget {
  const SchedulerApp({super.key, this.windowHost});
  final SchedulerWindowHost? windowHost;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Continuum — Engineering preview',
    debugShowCheckedModeBanner: false,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en', 'US'), Locale('en', 'GB')],
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: DeckColor.voidInk,
      colorScheme: ColorScheme.fromSeed(
        seedColor: DeckColor.coral,
        brightness: Brightness.dark,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xff1b243a),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xff171f32),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 13,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    home: SchedulerHome(windowHost: windowHost),
  );
}
