import 'package:flutter/material.dart';

/// Cores semânticas que mudam entre claro e escuro.
///
/// Vive como `ThemeExtension` em vez de constantes estáticas porque o app
/// precisa de modo escuro de verdade: entregador trabalha à noite, e tela
/// branca no escuro cega. Widget nenhum deve escolher cor por conta própria —
/// pede aqui e recebe a do tema ativo.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color brand;
  final Color brandSoft;
  final Color onBrand;
  final Color accent;

  final Color surface;
  final Color surfaceAlt;
  final Color surfaceSunken;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color border;
  final Color borderStrong;

  final Color success;
  final Color warning;
  final Color danger;

  /// Cor de cada estratégia de rota. O usuário aprende a reconhecer o card
  /// pela cor antes de ler o texto.
  final Color strategyFastest;
  final Color strategyShortest;
  final Color strategyNearestFirst;

  /// Sombra dos cards. No escuro ela some (sombra preta sobre fundo preto não
  /// faz nada) e a separação passa a vir da borda.
  final Color shadow;

  const AppColors({
    required this.brand,
    required this.brandSoft,
    required this.onBrand,
    required this.accent,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceSunken,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.borderStrong,
    required this.success,
    required this.warning,
    required this.danger,
    required this.strategyFastest,
    required this.strategyShortest,
    required this.strategyNearestFirst,
    required this.shadow,
  });

  static const light = AppColors(
    brand: Color(0xFF14603F),
    brandSoft: Color(0xFFD8EDE1),
    onBrand: Color(0xFFFFFFFF),
    accent: Color(0xFFEF5F2C),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDF2EE),
    surfaceSunken: Color(0xFFF5F8F6),
    textPrimary: Color(0xFF101C16),
    textSecondary: Color(0xFF56675D),
    textTertiary: Color(0xFF8A9891),
    border: Color(0xFFDCE5DF),
    borderStrong: Color(0xFFC2CFC7),
    success: Color(0xFF17803D),
    warning: Color(0xFFB97400),
    danger: Color(0xFFC62828),
    strategyFastest: Color(0xFF1565C0),
    strategyShortest: Color(0xFF2E7D32),
    strategyNearestFirst: Color(0xFF7B1FA2),
    shadow: Color(0x14101C16),
  );

  static const dark = AppColors(
    brand: Color(0xFF45BE85),
    brandSoft: Color(0xFF15382A),
    onBrand: Color(0xFF04150D),
    accent: Color(0xFFFF7A47),
    surface: Color(0xFF16201B),
    surfaceAlt: Color(0xFF1F2B25),
    surfaceSunken: Color(0xFF0D1411),
    textPrimary: Color(0xFFE9F1EB),
    textSecondary: Color(0xFF9FB2A7),
    textTertiary: Color(0xFF6F8177),
    border: Color(0xFF2B3931),
    borderStrong: Color(0xFF3C4E43),
    success: Color(0xFF4CC38A),
    warning: Color(0xFFE9A23B),
    danger: Color(0xFFF2635A),
    strategyFastest: Color(0xFF6FB4F5),
    strategyShortest: Color(0xFF7FCB84),
    strategyNearestFirst: Color(0xFFC79BE0),
    shadow: Color(0x00000000),
  );

  @override
  AppColors copyWith({
    Color? brand,
    Color? brandSoft,
    Color? onBrand,
    Color? accent,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceSunken,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? border,
    Color? borderStrong,
    Color? success,
    Color? warning,
    Color? danger,
    Color? strategyFastest,
    Color? strategyShortest,
    Color? strategyNearestFirst,
    Color? shadow,
  }) {
    return AppColors(
      brand: brand ?? this.brand,
      brandSoft: brandSoft ?? this.brandSoft,
      onBrand: onBrand ?? this.onBrand,
      accent: accent ?? this.accent,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      strategyFastest: strategyFastest ?? this.strategyFastest,
      strategyShortest: strategyShortest ?? this.strategyShortest,
      strategyNearestFirst: strategyNearestFirst ?? this.strategyNearestFirst,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      brand: Color.lerp(brand, other.brand, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      strategyFastest: Color.lerp(strategyFastest, other.strategyFastest, t)!,
      strategyShortest:
          Color.lerp(strategyShortest, other.strategyShortest, t)!,
      strategyNearestFirst:
          Color.lerp(strategyNearestFirst, other.strategyNearestFirst, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  /// Atalho para as cores do tema ativo: `context.colors.textSecondary`.
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
