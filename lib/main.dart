import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webapp/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/views/shared/app_shell.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';
import 'package:webapp/services/firestore_offline_service.dart';
import 'package:webapp/services/offline_queue_coordinator_service.dart';
import 'package:webapp/services/startup_splash.dart';
import 'package:webapp/utils/functions.dart';

const Duration _firebaseBootstrapTimeout = Duration(seconds: 6);
const Duration _firestoreBootstrapTimeout = Duration(seconds: 4);
const Duration _applicationBootstrapTimeout = Duration(seconds: 8);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  showStartupSplash();
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

  final bootstrapFuture = runZonedGuarded<Future<void>>(_bootstrapApplication, (
    error,
    stack,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
  });

  runApp(MyApp(bootstrapFuture: bootstrapFuture));
}

Future<void> _bootstrapApplication() async {
  try {
    await () async {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          ).timeout(_firebaseBootstrapTimeout);
        }
      } catch (_) {}
      try {
        await FirestoreOfflineService.initialize().timeout(
          _firestoreBootstrapTimeout,
        );
      } catch (_) {}
      unawaited(() async {
        try {
          await OfflineQueueCoordinatorService.instance.initialize();
        } catch (_) {}
      }());
      if (Firebase.apps.isNotEmpty) {
        unawaited(() async {
          try {
            await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
              true,
            );
          } catch (_) {}
        }());
      }
    }().timeout(
      _applicationBootstrapTimeout,
      onTimeout: () {},
    );
  } finally {}
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
  const MyApp({super.key, required this.bootstrapFuture});

  final Future<void>? bootstrapFuture;

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
        datePickerTheme: DatePickerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          headerBackgroundColor: Colors.white,
          headerForegroundColor: AppColors.textPrimary,
          weekdayStyle: const TextStyle(color: AppColors.textSecondary),
          dayForegroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return AppColors.textPrimary;
          }),
          dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primaryColor;
            }
            return Colors.white;
          }),
          todayForegroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return AppColors.primaryColor;
          }),
          todayBackgroundColor: WidgetStateProperty.all(Colors.white),
          yearForegroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return AppColors.textPrimary;
          }),
          yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primaryColor;
            }
            return Colors.white;
          }),
          rangeSelectionBackgroundColor: AppColors.primaryColor.withValues(
            alpha: 0.12,
          ),
          rangeSelectionOverlayColor: WidgetStateProperty.all(
            Colors.transparent,
          ),
          cancelButtonStyle: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
          ),
          confirmButtonStyle: TextButton.styleFrom(
            foregroundColor: AppColors.primaryColor,
          ),
          dividerColor: AppColors.primaryBorder,
        ),
        timePickerTheme: TimePickerThemeData(
          backgroundColor: Colors.white,
          dialBackgroundColor: const Color(0xFFF7F4FF),
          hourMinuteColor: const Color(0xFFF7F4FF),
          hourMinuteTextColor: AppColors.textPrimary,
          dayPeriodColor: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primaryColor;
            }
            return Colors.white;
          }),
          dayPeriodTextColor: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return AppColors.textPrimary;
          }),
          dialHandColor: AppColors.primaryColor,
          dialTextColor: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return AppColors.textPrimary;
          }),
          entryModeIconColor: AppColors.primaryColor,
          helpTextStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
          hourMinuteTextStyle: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
          dayPeriodTextStyle: const TextStyle(fontWeight: FontWeight.w700),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
          ),
          cancelButtonStyle: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
          ),
          confirmButtonStyle: TextButton.styleFrom(
            foregroundColor: AppColors.primaryColor,
          ),
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
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AppColors.primaryColor,
          selectionColor: AppColors.primaryColor.withValues(alpha: 0.32),
          selectionHandleColor: AppColors.primaryColor,
        ),
      ),
      home: _BootstrapGate(bootstrapFuture: bootstrapFuture),
    );
  }
}

class _BootstrapGate extends StatelessWidget {
  const _BootstrapGate({required this.bootstrapFuture});

  final Future<void>? bootstrapFuture;

  @override
  Widget build(BuildContext context) {
    if (bootstrapFuture == null) {
      return const _AppErrorFallback(
        details: FlutterErrorDetails(
          exception: 'Application bootstrap did not start.',
        ),
      );
    }

    return FutureBuilder<void>(
      future: bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StartupReady(
            child: _AppErrorFallback(
              details: FlutterErrorDetails(
                exception: snapshot.error ?? 'Application bootstrap failed.',
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AppBootstrapLoadingScreen();
        }
        return const AppShell();
      },
    );
  }
}

class _StartupReady extends StatefulWidget {
  const _StartupReady({required this.child});

  final Widget child;

  @override
  State<_StartupReady> createState() => _StartupReadyState();
}

class _StartupReadyState extends State<_StartupReady> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        dismissStartupSplash();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AppBootstrapLoadingScreen extends StatelessWidget {
  const _AppBootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: ColoredBox(
          color: Color(0xFF5C33CF),
          child: Center(
            child: AppPageLoading(
              message: 'Starting Paltranco and preparing offline data ...',
              compact: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppErrorFallback extends StatelessWidget {
  const _AppErrorFallback({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final exceptionText = exactUserErrorMessage(
      details.exception,
      fallback: details.exceptionAsString(),
    );
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Application error',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                exceptionText,
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
