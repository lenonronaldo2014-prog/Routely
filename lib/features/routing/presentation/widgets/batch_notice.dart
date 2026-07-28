import 'package:flutter/material.dart';

import '../../../../core/config/plan_limits.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/route_plan.dart';

/// Explica por que nem todas as entregas entraram nesta rota.
///
/// O tom importa: o app não está bloqueando nada — o usuário cadastrou tudo, e
/// tudo será entregue. Só vai em grupos. Tratar isso como erro ou como parede
/// de pagamento faria o app parecer quebrado; tratar como organização do dia é
/// o que de fato é.
class BatchNotice extends StatelessWidget {
  final RoutePlan plan;

  const BatchNotice({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final limit = plan.tier.maxStopsPerRoute;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: c.brand.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.layers_rounded, size: 18, color: c.brand),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Grupo 1 de ${plan.totalBatches}',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.brand,
                  borderRadius: AppRadius.smAll,
                ),
                child: Text(
                  plan.tier == PlanTier.free ? 'GRÁTIS' : 'PRO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: c.onBrand,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Estas são as $limit entregas mais próximas de você. '
            'As outras ${plan.deferredCount} entram no próximo grupo — '
            'calculado a partir de onde você estiver ao terminar este.',
            style: TextStyle(
              fontSize: 13,
              color: c.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
