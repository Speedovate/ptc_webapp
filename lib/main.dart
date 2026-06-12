import 'dart:async';
import 'dart:ui';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/firebase_options.dart';
import 'package:webapp/views/shared/app_shell.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
      };
      ErrorWidget.builder = (details) => _AppErrorFallback(details: details);

      PlatformDispatcher.instance.onError = (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
        return true;
      };

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
      runApp(const MyApp());
    },
    (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}

TextTheme _withTextHeight(TextTheme textTheme, double height) {
  TextStyle? apply(TextStyle? style) => style?.copyWith(height: height);

  return textTheme.copyWith(
    displayLarge: apply(textTheme.displayLarge),
    displayMedium: apply(textTheme.displayMedium),
    displaySmall: apply(textTheme.displaySmall),
    headlineLarge: apply(textTheme.headlineLarge),
    headlineMedium: apply(textTheme.headlineMedium),
    headlineSmall: apply(textTheme.headlineSmall),
    titleLarge: apply(textTheme.titleLarge),
    titleMedium: apply(textTheme.titleMedium),
    titleSmall: apply(textTheme.titleSmall),
    bodyLarge: apply(textTheme.bodyLarge),
    bodyMedium: apply(textTheme.bodyMedium),
    bodySmall: apply(textTheme.bodySmall),
    labelLarge: apply(textTheme.labelLarge),
    labelMedium: apply(textTheme.labelMedium),
    labelSmall: apply(textTheme.labelSmall),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final baseLightTheme = ThemeData.light();
    final colorScheme = ColorScheme.fromSeed(seedColor: AppColors.primaryColor)
        .copyWith(
          primary: AppColors.primaryColor,
          onPrimary: Colors.white,
          secondary: AppColors.primaryColor,
          onSecondary: Colors.white,
          surface: Colors.white,
          onSurface: AppColors.textPrimary,
          error: AppColors.danger,
          onError: Colors.white,
          outline: AppColors.primaryBorder,
        );

    return MaterialApp(
      title: 'Paltranco Digital Platform',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            final currentFocus = FocusScope.of(context);
            if (!currentFocus.hasPrimaryFocus &&
                currentFocus.focusedChild != null) {
              currentFocus.unfocus();
            }
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        colorScheme: colorScheme,
        primaryColor: AppColors.primaryColor,
        scaffoldBackgroundColor: Colors.white,
        canvasColor: Colors.white,
        cardColor: Colors.white,
        dividerColor: AppColors.primaryBorder,
        hintColor: AppColors.textSecondary,
        shadowColor: const Color(0x120E0A1F),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        textTheme: _withTextHeight(baseLightTheme.textTheme, 1.2),
        primaryTextTheme: _withTextHeight(baseLightTheme.primaryTextTheme, 1.2),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          contentTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          actionTextColor: Colors.white,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: AppColors.primaryColor,
          selectionColor: AppColors.primaryBorder,
          selectionHandleColor: AppColors.primaryColor,
        ),
      ),
      home: AppShell(),
    );
  }
}

class _AppErrorFallback extends StatelessWidget {
  const _AppErrorFallback({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8F7FC),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primaryBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120E0A1F),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Something went wrong',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Please refresh the page and try again.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
