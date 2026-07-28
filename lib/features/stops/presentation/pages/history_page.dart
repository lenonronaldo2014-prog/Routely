import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/responsive_body.dart';
import '../../../../injection_container.dart';
import '../../domain/entities/delivery_record.dart';
import '../cubit/history_cubit.dart';

/// O que já foi entregue, por dia.
///
/// Existe porque o registro do próprio trabalho é do entregador. Antes, limpar
/// as concluídas apagava tudo e no fim do mês não dava para saber quantas
/// entregas foram feitas nem quanto se rodou.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<HistoryCubit>()..load(),
      child: const _HistoryView(),
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        actions: [
          BlocBuilder<HistoryCubit, HistoryState>(
            builder: (context, state) {
              if (state.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Apagar histórico',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _confirmClear(context),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<HistoryCubit, HistoryState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.isEmpty) return const _EmptyHistory();

          return ResponsiveBody(
            wide: true,
            child: ListView(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.xxl,
              ),
              children: [
                _TotalsCard(state: state),
                const SizedBox(height: AppSpacing.lg),
                ...state.days.map((day) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: _DaySection(day: day),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final cubit = context.read<HistoryCubit>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apagar o histórico?'),
        content: const Text(
          'Todo o registro de entregas concluídas será perdido. '
          'Não dá para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirmed == true) await cubit.clear();
  }
}

class _TotalsCard extends StatelessWidget {
  final HistoryState state;

  const _TotalsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.brand, Color.lerp(c.brand, Colors.black, 0.25)!],
        ),
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        children: [
          _Total(
            value: '${state.totalDelivered}',
            caption: state.totalDelivered == 1 ? 'entrega' : 'entregas',
          ),
          _Total(
            value: '${state.days.length}',
            caption: state.days.length == 1 ? 'dia' : 'dias',
          ),
          if (state.totalDistanceMeters > 0)
            _Total(
              value: _formatKm(state.totalDistanceMeters),
              caption: 'rodados',
            ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  final String value;
  final String caption;

  const _Total({required this.value, required this.caption});

  @override
  Widget build(BuildContext context) {
    final onBrand = context.colors.onBrand;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                height: 1,
                color: onBrand,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            caption,
            style: TextStyle(
              fontSize: 12,
              color: onBrand.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  final DeliveryDay day;

  const _DaySection({required this.day});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _formatDay(day.day),
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            Text(
              [
                '${day.delivered} entregue${day.delivered == 1 ? "" : "s"}',
                if (day.failed > 0) '${day.failed} não entregue',
                if (day.hasDistance) _formatKm(day.distanceMeters),
              ].join(' · '),
              style: TextStyle(fontSize: 12.5, color: c.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...day.records.map((record) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _RecordTile(record: record),
            )),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  final DeliveryRecord record;

  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final delivered = record.wasDelivered;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      child: Row(
        children: [
          Icon(
            delivered ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 20,
            color: delivered ? c.success : c.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.shortAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (record.locality.isNotEmpty)
                  Text(
                    record.locality,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.textTertiary),
                  ),
              ],
            ),
          ),
          Text(
            _formatTime(record.completedAt),
            style: TextStyle(fontSize: 12.5, color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Center(
      child: ResponsiveBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 54, color: c.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Nada no histórico ainda',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Quando você limpar as entregas concluídas, elas vêm para cá — '
              'com data, hora e quilometragem.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                color: c.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatKm(double meters) {
  final km = meters / 1000;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

String _formatTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';

String _formatDay(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final difference = today.difference(day).inDays;

  if (difference == 0) return 'Hoje';
  if (difference == 1) return 'Ontem';

  const months = [
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
    'jul', 'ago', 'set', 'out', 'nov', 'dez',
  ];

  return '${day.day} de ${months[day.month - 1]}'
      '${day.year == now.year ? '' : ' de ${day.year}'}';
}
