// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error surfaces (instead of silent white screen)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };
  ErrorWidget.builder = (FlutterErrorDetails details) => Material(
        color: const Color(0xFF0F172A),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SelectableText(
              '🔥 Uncaught error:\n\n${details.exceptionAsString()}\n\n${details.stack}',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.left,
            ),
          ),
        ),
      );

  // Catch async zone errors too
  runZonedGuarded(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    runApp(const GameScapeAdminApp());
  }, (error, stack) {
    // last-resort logging
    // (still shows via ErrorWidget because we set builder above)
    // ignore: avoid_print
    print('Zoned error: $error\n$stack');
  });
}

class GameScapeAdminApp extends StatelessWidget {
  const GameScapeAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = AppRouter.router;
    return MaterialApp.router(
      title: 'GameScape Admin',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
