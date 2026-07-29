import 'package:shared_preferences/shared_preferences.dart';

/// Contador de chamadas por dia, para não estourar o plano gratuito.
///
/// Fica em `SharedPreferences` e não no banco de propósito: é um contador
/// trivial que precisa ser lido antes de cada chamada, e abrir transação no
/// SQLite para incrementar um inteiro seria caro à toa.
///
/// O contador zera sozinho quando a data muda. Não guarda histórico — saber
/// quanto foi gasto ontem não muda nenhuma decisão de hoje.
class DailyQuota {
  final SharedPreferences prefs;
  final String name;
  final int budget;

  /// Injetável para o teste poder virar o dia sem esperar meia-noite.
  final DateTime Function() clock;

  DailyQuota({
    required this.prefs,
    required this.name,
    required this.budget,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  String get _dayKey => 'quota_${name}_day';
  String get _countKey => 'quota_${name}_count';

  /// Data local no formato `2026-07-29`. Local e não UTC porque o limite que
  /// interessa ao usuário vira junto com o dia dele de trabalho.
  String get _today {
    final now = clock();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  int get spentToday {
    if (prefs.getString(_dayKey) != _today) return 0;
    return prefs.getInt(_countKey) ?? 0;
  }

  int get remaining {
    final left = budget - spentToday;
    return left > 0 ? left : 0;
  }

  bool get hasRoom => remaining > 0;

  Future<void> spend([int amount = 1]) async {
    final today = _today;

    // Dia virou: reinicia em vez de somar em cima do contador de ontem.
    if (prefs.getString(_dayKey) != today) {
      await prefs.setString(_dayKey, today);
      await prefs.setInt(_countKey, amount);
      return;
    }

    await prefs.setInt(_countKey, spentToday + amount);
  }
}
