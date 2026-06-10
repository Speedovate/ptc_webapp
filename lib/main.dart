import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/views/shared/app_shell.dart';

void main() {
  runApp(const MyApp());
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
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryColor,
    ).copyWith(
      primary: AppColors.primaryColor,
      onPrimary: Colors.white,
      secondary: AppColors.primaryColor,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.textPrimary,
      error: const Color(0xFFD94B4B),
      onError: Colors.white,
      outline: AppColors.primaryBorder,
    );

    return MaterialApp(
      title: 'Paltranco',
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
        textTheme: _withTextHeight(baseLightTheme.textTheme, 1.2),
        primaryTextTheme: _withTextHeight(
          baseLightTheme.primaryTextTheme,
          1.2,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
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
