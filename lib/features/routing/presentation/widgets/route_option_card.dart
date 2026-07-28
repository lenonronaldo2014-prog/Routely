import 'package:flutter/material.dart';

import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/entities/route_option.dart';
import '../../domain/entities/route_strategy.dart';

class RouteOptionCard extends StatelessWidget {
  final RouteOption option;

  /// Marca a opção com o menor tempo total. É só uma dica — a escolha continua
  /// sendo do usuário, que sabe coisas que o algoritmo não sabe.
  final bool isRecommended;

  final VoidCallback onTap;

  const RouteOptionCard({
    super.key,
    required this.option,
    required this.onTap,
    this.isRecommended = false,
  });

  Color _accent(BuildContext context) {
    final c = context.colors;
    return switch (option.strategy) {
      RouteStrategy.fastest => c.strategyFastest,
      RouteStrategy.shortest => c.strategyShortest,
      RouteStrategy.nearestFirst => c.strategyNearestFirst,
    };
  }

  IconData get _icon => switch (option.strategy) {
        RouteStrategy.fastest => Icons.bolt_rounded,
        RouteStrategy.shortest => Icons.local_gas_station_rounded,
        RouteStrategy.nearestFirst => Icons.my_location_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = _accent(context);
    final compact = AppBreakpoints.isCompact(context);

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      borderColor: isRecommended ? accent : c.border,
      borderWidth: isRecommended ? 2 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Faixa colorida no topo — o usuário reconhece a estratégia pela cor
          // antes de ler qualquer texto.
          Container(height: 4, color: accent),
          Padding(
            padding: EdgeInsets.all(compact ? AppSpacing.sm + 2 : AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.13),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Icon(_icon, color: accent, size: 21),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.strategy.label,
                            style: TextStyle(
                              fontSize: compact ? 16 : 17.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            option.strategy.description,
                            style: TextStyle(
                              fontSize: 12.8,
                              color: c.textSecondary,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isRecommended) ...[
                      const SizedBox(width: AppSpacing.xs),
                      AppChip(label: 'SUGERIDA', color: accent, filled: true),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _MetricRow(option: option, accent: accent),
                const SizedBox(height: AppSpacing.sm),
                _Breakdown(option: option),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final RouteOption option;
  final Color accent;

  const _MetricRow({required this.option, required this.accent});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // Tudo flexível: numa tela de 320dp, "2h 15min" somado a "48,0 km" passa
    // da largura disponível. Sem isso o card estoura em celular pequeno — que
    // é justamente o aparelho mais comum na base.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // O tempo total é a informação que decide a escolha, então ganha o
        // maior peso visual da tela.
        Flexible(
          flex: 5,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              option.formattedDuration,
              maxLines: 1,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2,
                height: 1,
                color: accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: _SmallMetric(
                    icon: Icons.straighten_rounded,
                    value: option.formattedDistance,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _SmallMetric(
                  icon: Icons.inventory_2_outlined,
                  value: '${option.stopCount}',
                ),
              ],
            ),
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textTertiary),
      ],
    );
  }
}

class _SmallMetric extends StatelessWidget {
  final IconData icon;
  final String value;

  const _SmallMetric({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: c.textTertiary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Barra proporcional mostrando quanto do tempo é dirigindo e quanto é parado
/// entregando. Deixa explícito que o tempo de parada está na conta — que é a
/// diferença entre uma estimativa honesta e uma otimista.
class _Breakdown extends StatelessWidget {
  final RouteOption option;

  const _Breakdown({required this.option});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = option.totalDurationSeconds;
    final drivingRatio = total == 0 ? 1.0 : option.travelDurationSeconds / total;
    final serviceMinutes = (option.serviceDurationSeconds / 60).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Row(
            children: [
              Expanded(
                flex: (drivingRatio * 1000).round().clamp(1, 1000),
                child: Container(height: 5, color: c.textSecondary),
              ),
              Expanded(
                flex: ((1 - drivingRatio) * 1000).round().clamp(1, 1000),
                child: Container(height: 5, color: c.textTertiary.withValues(alpha: 0.4)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${option.formattedTravelDuration} dirigindo · ${serviceMinutes}min nas entregas',
          style: TextStyle(fontSize: 12, color: c.textTertiary),
        ),
      ],
    );
  }
}
