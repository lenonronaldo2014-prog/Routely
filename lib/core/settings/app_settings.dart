import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/plan_limits.dart';

/// Preferências que afetam o cálculo da rota.
///
/// Ficam expostas ao usuário porque só ele sabe seu contexto: quem entrega
/// documento em prédio comercial gasta 2 min por parada; quem entrega móvel em
/// condomínio gasta 15. Um valor fixo no código erraria para os dois.
class AppSettings {
  static const _kServiceTimeMinutes = 'service_time_minutes';
  static const _kAverageSpeedKmh = 'average_speed_kmh';
  static const _kPlanTier = 'plan_tier';
  static const _kThemeMode = 'theme_mode';

  static const int defaultServiceTimeMinutes = 3;
  static const double defaultAverageSpeedKmh = 28.0;

  final SharedPreferences prefs;

  AppSettings(this.prefs);

  /// Tempo médio parado em cada entrega: estacionar, achar o cliente, entregar.
  Duration get serviceTimePerStop => Duration(
        minutes: prefs.getInt(_kServiceTimeMinutes) ?? defaultServiceTimeMinutes,
      );

  Future<void> setServiceTimeMinutes(int minutes) =>
      prefs.setInt(_kServiceTimeMinutes, minutes.clamp(0, 60));

  /// Só usada pela estimativa offline; quando há um serviço de rotas real, ele
  /// já devolve o tempo pronto.
  double get averageSpeedKmh =>
      prefs.getDouble(_kAverageSpeedKmh) ?? defaultAverageSpeedKmh;

  Future<void> setAverageSpeedKmh(double kmh) =>
      prefs.setDouble(_kAverageSpeedKmh, kmh.clamp(5.0, 120.0));

  /// Plano atual. Guardado localmente por enquanto; quando existir assinatura
  /// de verdade, o valor passa a vir do servidor e este getter vira o cache.
  PlanTier get planTier {
    final stored = prefs.getString(_kPlanTier);
    return PlanTier.values.firstWhere(
      (t) => t.name == stored,
      orElse: () => PlanTier.free,
    );
  }

  Future<void> setPlanTier(PlanTier tier) =>
      prefs.setString(_kPlanTier, tier.name);

  int get maxStopsPerRoute => planTier.maxStopsPerRoute;

  /// Tema escolhido. O padrão é seguir o sistema — quem já deixou o celular no
  /// escuro não quer um app estourando branco na cara às 22h.
  ThemeMode get themeMode {
    final stored = prefs.getString(_kThemeMode);
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    return prefs.setString(_kThemeMode, value);
  }
}
