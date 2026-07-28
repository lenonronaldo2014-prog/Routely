import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/settings/app_settings.dart';

/// Preferências do app.
///
/// Vive no topo da árvore porque o tema precisa chegar ao `MaterialApp` — mudar
/// de claro para escuro tem que refletir na hora, sem reiniciar.
class SettingsCubit extends Cubit<SettingsState> {
  final AppSettings settings;

  SettingsCubit(this.settings)
      : super(SettingsState(
          themeMode: settings.themeMode,
          serviceTimeMinutes: settings.serviceTimePerStop.inMinutes,
          averageSpeedKmh: settings.averageSpeedKmh,
        ));

  Future<void> setThemeMode(ThemeMode mode) async {
    emit(state.copyWith(themeMode: mode));
    await settings.setThemeMode(mode);
  }

  Future<void> setServiceTimeMinutes(int minutes) async {
    final clamped = minutes.clamp(0, 60);
    emit(state.copyWith(serviceTimeMinutes: clamped));
    await settings.setServiceTimeMinutes(clamped);
  }

  Future<void> setAverageSpeedKmh(double kmh) async {
    final clamped = kmh.clamp(5.0, 120.0);
    emit(state.copyWith(averageSpeedKmh: clamped));
    await settings.setAverageSpeedKmh(clamped);
  }
}

class SettingsState extends Equatable {
  final ThemeMode themeMode;

  /// Tempo médio parado em cada entrega. É o maior fator de precisão da
  /// estimativa e só o usuário sabe o valor certo para o trabalho dele.
  final int serviceTimeMinutes;

  final double averageSpeedKmh;

  const SettingsState({
    required this.themeMode,
    required this.serviceTimeMinutes,
    required this.averageSpeedKmh,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    int? serviceTimeMinutes,
    double? averageSpeedKmh,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      serviceTimeMinutes: serviceTimeMinutes ?? this.serviceTimeMinutes,
      averageSpeedKmh: averageSpeedKmh ?? this.averageSpeedKmh,
    );
  }

  @override
  List<Object?> get props => [themeMode, serviceTimeMinutes, averageSpeedKmh];
}
