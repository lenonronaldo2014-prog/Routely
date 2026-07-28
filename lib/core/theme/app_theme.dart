import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

class AppTheme {
  AppTheme._();

  /// Alvo mínimo de toque, acima dos 48dp do Material: o usuário costuma estar
  /// de luva, em movimento e com o celular numa mão só.
  static const double minTouchTarget = 56;

  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.brand,
      onPrimary: c.onBrand,
      primaryContainer: c.brandSoft,
      onPrimaryContainer: isDark ? c.textPrimary : c.brand,
      secondary: c.accent,
      onSecondary: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceAlt,
      onSurfaceVariant: c.textSecondary,
      outline: c.border,
      outlineVariant: c.border,
      error: c.danger,
      onError: Colors.white,
      shadow: c.shadow,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
    );

    return base.copyWith(
      extensions: [c],
      scaffoldBackgroundColor: c.surfaceSunken,
      canvasColor: c.surface,

      // Barra clara com título em texto normal, em vez do bloco de cor sólida.
      // Deixa a cor da marca livre para destacar o que importa — o botão de
      // ação e os cards de rota — em vez de gastá-la no topo de toda tela.
      appBarTheme: AppBarTheme(
        backgroundColor: c.surfaceSunken,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: c.surfaceSunken,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: c.surfaceSunken,
              ),
      ),

      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: c.border),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.onBrand,
          disabledBackgroundColor: c.surfaceAlt,
          disabledForegroundColor: c.textTertiary,
          minimumSize: const Size.fromHeight(minTouchTarget),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.onBrand,
          minimumSize: const Size.fromHeight(minTouchTarget),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size.fromHeight(minTouchTarget),
          side: BorderSide(color: c.borderStrong, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.brand,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md + 2,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: c.brand, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: c.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: c.danger, width: 2),
        ),
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 15),
        floatingLabelStyle: TextStyle(
          color: c.brand,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(color: c.textTertiary, fontSize: 15),
        helperStyle: TextStyle(color: c.textTertiary, fontSize: 12.5),
        errorStyle: TextStyle(color: c.danger, fontSize: 12.5),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: Colors.white,
        elevation: 3,
        highlightElevation: 6,
        extendedTextStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.1,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? c.surfaceAlt : const Color(0xFF1E2B23),
        contentTextStyle: TextStyle(
          color: isDark ? c.textPrimary : Colors.white,
          fontSize: 14.5,
          height: 1.35,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        insetPadding: const EdgeInsets.all(AppSpacing.md),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: TextStyle(
          color: c.textSecondary,
          fontSize: 15,
          height: 1.4,
        ),
      ),

      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brand,
        linearTrackColor: c.surfaceAlt,
        circularTrackColor: c.surfaceAlt,
      ),

      iconTheme: IconThemeData(color: c.textSecondary),

      textTheme: _textTheme(base.textTheme, c),
    );
  }

  /// Escala tipográfica fechada, com títulos em peso alto e tracking negativo
  /// — o que dá a densidade "de produto" sem precisar de fonte customizada
  /// (que exigiria baixar arquivo e brigaria com o requisito de funcionar
  /// offline).
  static TextTheme _textTheme(TextTheme base, AppColors c) {
    return base
        .copyWith(
          displaySmall: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            height: 1.1,
          ),
          headlineMedium: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.15,
          ),
          headlineSmall: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1.2,
          ),
          titleLarge: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
          bodyLarge: const TextStyle(fontSize: 15.5, height: 1.4),
          bodyMedium: const TextStyle(fontSize: 14, height: 1.4),
          bodySmall: const TextStyle(fontSize: 12.5, height: 1.35),
          labelLarge: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        )
        .apply(bodyColor: c.textPrimary, displayColor: c.textPrimary);
  }
}
