import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/active_route.dart';

/// Card de retomada na tela inicial.
///
/// É a primeira coisa que o entregador vê ao abrir o app com um roteiro em
/// curso — inclusive depois do celular morrer e ligar de novo. Mostra o que
/// falta, não o total: passadas 5 de 8 entregas, "faltam 25min" é o número
/// útil.
class ActiveRouteCard extends StatelessWidget {
  final ActiveRoute route;
  final VoidCallback onContinue;

  const ActiveRouteCard({
    super.key,
    required this.route,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final next = route.nextStop;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onContinue,
        borderRadius: AppRadius.lgAll,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.brand, Color.lerp(c.brand, Colors.black, 0.25)!],
            ),
            borderRadius: AppRadius.lgAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.route_rounded, size: 17, color: c.onBrand),
                  const SizedBox(width: 6),
                  Text(
                    'ROTA EM ANDAMENTO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: c.onBrand.withValues(alpha: 0.85),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${route.deliveredCount}/${route.totalStops}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.onBrand,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: route.progress),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: c.onBrand.withValues(alpha: 0.22),
                    valueColor: AlwaysStoppedAnimation(c.onBrand),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (next != null) ...[
                Text(
                  'PRÓXIMA',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: c.onBrand.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  next.shortAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: c.onBrand,
                  ),
                ),
                if (next.locality.isNotEmpty)
                  Text(
                    next.locality,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.onBrand.withValues(alpha: 0.75),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
              ] else ...[
                Text(
                  'Todas as entregas desta rota foram concluídas.',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: c.onBrand,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: [
                  if (next != null) ...[
                    _Pill(
                      icon: Icons.schedule_rounded,
                      label: '${route.formattedRemainingDuration} restantes',
                      color: c.onBrand,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _Pill(
                      icon: Icons.straighten_rounded,
                      label: route.formattedRemainingDistance,
                      color: c.onBrand,
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: c.onBrand,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Pill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: AppRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
