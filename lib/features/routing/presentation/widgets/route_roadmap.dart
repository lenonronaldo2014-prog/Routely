import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../stops/domain/entities/delivery_stop.dart';
import '../../domain/entities/route_option.dart';

/// Linha do tempo vertical do roteiro: onde você está, primeira parada,
/// segunda, e assim por diante até o fim.
///
/// Uma lista solta de endereços obriga o entregador a ler tudo para entender a
/// sequência. O traçado contínuo com os números na linha faz a ordem ser
/// entendida de relance — que é o que importa quando ele olha a tela parado no
/// semáforo.
class RouteRoadmap extends StatelessWidget {
  final List<RouteLeg> legs;

  /// Índice do primeiro trecho ainda pendente. Tudo antes aparece esmaecido e
  /// com o traço tracejado.
  final int currentIndex;

  final void Function(DeliveryStop stop)? onTapStop;

  /// Numeração exibida ao lado de cada parada. Quando o roteiro já começou, a
  /// posição real na rota não é o índice desta lista.
  final int startNumber;

  const RouteRoadmap({
    super.key,
    required this.legs,
    this.currentIndex = 0,
    this.onTapStop,
    this.startNumber = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OriginNode(hasNext: legs.isNotEmpty),
        for (var i = 0; i < legs.length; i++)
          _RoadmapNode(
            leg: legs[i],
            number: startNumber + i,
            isLast: i == legs.length - 1,
            isDone: legs[i].to.status != StopStatus.pending,
            isCurrent: i == currentIndex,
            onTap: onTapStop == null ? null : () => onTapStop!(legs[i].to),
          ),
      ],
    );
  }
}

/// O ponto de partida — "você está aqui".
class _OriginNode extends StatelessWidget {
  final bool hasNext;

  const _OriginNode({required this.hasNext});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _RoadmapMetrics.gutter,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.textTertiary, width: 3),
                  ),
                ),
                if (hasNext)
                  Expanded(
                    child: Container(width: 2, color: c.border),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Onde você está',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: c.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadmapNode extends StatelessWidget {
  final RouteLeg leg;
  final int number;
  final bool isLast;
  final bool isDone;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _RoadmapNode({
    required this.leg,
    required this.number,
    required this.isLast,
    required this.isDone,
    required this.isCurrent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final nodeColor = isDone
        ? c.success
        : isCurrent
            ? c.brand
            : c.surfaceAlt;

    final numberColor = isDone
        ? Colors.white
        : isCurrent
            ? c.onBrand
            : c.textSecondary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _RoadmapMetrics.gutter,
            child: Column(
              children: [
                Container(
                  width: _RoadmapMetrics.nodeSize,
                  height: _RoadmapMetrics.nodeSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: nodeColor,
                    shape: BoxShape.circle,
                    border: isCurrent
                        ? Border.all(color: c.brand, width: 3)
                        : null,
                  ),
                  child: isDone
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white)
                      : Text(
                          '$number',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: numberColor,
                          ),
                        ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isDone ? c.success.withValues(alpha: 0.4) : c.border,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
              child: _StopBlock(
                leg: leg,
                isDone: isDone,
                isCurrent: isCurrent,
                onTap: onTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopBlock extends StatelessWidget {
  final RouteLeg leg;
  final bool isDone;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _StopBlock({
    required this.leg,
    required this.isDone,
    required this.isCurrent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stop = leg.to;
    final minutes = (leg.durationSeconds / 60).round();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // O trecho percorrido até esta parada.
              Text(
                '${RouteOption.formatDistance(leg.distanceMeters)} · ${minutes}min',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(height: 3),
              if (stop.label != null) ...[
                Text(
                  stop.label!,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: c.accent,
                  ),
                ),
                const SizedBox(height: 1),
              ],
              Text(
                stop.shortAddress,
                style: TextStyle(
                  fontSize: isCurrent ? 17 : 15.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  height: 1.25,
                  color: isDone ? c.textTertiary : c.textPrimary,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                  decorationColor: c.textTertiary,
                ),
              ),
              if (stop.locality.isNotEmpty)
                Text(
                  stop.locality,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDone ? c.textTertiary : c.textSecondary,
                  ),
                ),
              if (stop.complement != null)
                Text(
                  stop.complement!,
                  style: TextStyle(fontSize: 12, color: c.textTertiary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoadmapMetrics {
  _RoadmapMetrics._();

  static const double nodeSize = 30;
  static const double gutter = 42;
}
