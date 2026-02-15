import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'config/app_config.dart';
import 'features/home/home_screen.dart';
import 'ui/app_colors.dart';

class SentiChiPiantaApp extends StatelessWidget {
  const SentiChiPiantaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.background,
      primary: AppColors.primary,
      secondary: AppColors.primarySoft,
      onPrimary: Colors.white,
    );

    final textTheme = GoogleFonts.dmSerifDisplayTextTheme(
      ThemeData.light().textTheme,
    ).copyWith(
      bodyLarge: GoogleFonts.dmSans(),
      bodyMedium: GoogleFonts.dmSans(),
      bodySmall: GoogleFonts.dmSans(),
      labelLarge: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Senti Chi Pianta',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        textTheme: textTheme,
        scaffoldBackgroundColor: AppColors.background,
        cardColor: AppColors.card,
        dividerColor: AppColors.outline,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textDark,
            side: const BorderSide(color: AppColors.outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.card,
          selectedColor: AppColors.primarySoft,
          checkmarkColor: AppColors.textDark,
          side: const BorderSide(color: AppColors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          labelStyle: textTheme.labelMedium?.copyWith(color: AppColors.textDark),
          secondaryLabelStyle:
              textTheme.labelMedium?.copyWith(color: AppColors.textDark),
          disabledColor: AppColors.outline,
          brightness: Brightness.light,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.textDark,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.card,
          indicatorColor: AppColors.primarySoft,
          labelTextStyle: WidgetStatePropertyAll(
            textTheme.labelSmall?.copyWith(color: AppColors.textDark),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
      home: const HomeScreen(),
      builder: (context, child) {
        if (AppConfig.isConfigured) {
          return child ?? const SizedBox.shrink();
        }
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: _ConfigBanner(),
            ),
          ],
        );
      },
    );
  }
}

class _ConfigBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      color: const Color(0xFF2E3C2F),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.settings, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Config mancante: imposta SUPABASE_URL, SUPABASE_ANON_KEY e CLAUDE_API_KEY (oppure CLAUDE_ENDPOINT) con --dart-define.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
