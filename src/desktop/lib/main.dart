import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'desktop_window.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DesktopWindowHost? host;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    host = DesktopWindowHost();
    await host.initialize();
  }
  runApp(SchedulerApp(windowHost: host));
}
