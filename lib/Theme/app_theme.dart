import 'package:flutter/material.dart';

/// Red / light-red palette used across the whole BA app.
class AppColors {
  AppColors._();

  static const red = Color(0xFFE53935); // primary
  static const redDeep = Color(0xFFB71C1C); // dark accent
  static const redBright = Color(0xFFFF5252); // gradient start
  static const coral = Color(0xFFFF8A80); // soft accent
  static const redLight = Color(0xFFFFCDD2); // light red
  static const redTint = Color(0xFFFFEBEE); // very light red
  static const bg = Color(0xFFFFF6F6); // page background
  static const card = Colors.white;

  static const text = Color(0xFF2A1A1A);
  static const textDim = Color(0xFF7B6A6A);
  static const border = Color(0xFFF6D6D6);
  static const success = Color(0xFF2E9E6B);
  static const warning = Color(0xFFF5A524);
}

class AppGradients {
  AppGradients._();

  static const primary = LinearGradient(
    colors: [AppColors.redBright, AppColors.redDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const soft = LinearGradient(
    colors: [AppColors.coral, AppColors.red],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const horizontal = LinearGradient(
    colors: [AppColors.redBright, AppColors.red, AppColors.redDeep],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const success = LinearGradient(
    colors: [Color(0xFF43C59E), Color(0xFF2E9E6B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  AppTheme._();

  static const _font = 'ClashGrotesk';

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.red,
      primary: AppColors.red,
      secondary: AppColors.coral,
      surface: Colors.white,
    );

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: _font,
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.text),
        titleTextStyle: TextStyle(
          fontFamily: _font,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: AppColors.text,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.text,
        contentTextStyle: const TextStyle(
          fontFamily: _font,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border(AppColors.border),
        enabledBorder: border(AppColors.border),
        focusedBorder: border(AppColors.red, 1.6),
        errorBorder: border(AppColors.redDeep),
        focusedErrorBorder: border(AppColors.redDeep, 1.6),
        labelStyle: const TextStyle(color: AppColors.textDim),
        hintStyle: const TextStyle(color: Color(0xFFB9A7A7)),
        prefixIconColor: AppColors.red,
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.red),
      dividerColor: AppColors.border,
    );
  }
}
