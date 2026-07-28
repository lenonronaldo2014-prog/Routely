import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Card padrão do app: borda sutil + sombra suave no claro, borda um pouco
/// mais presente no escuro (onde sombra preta não aparece).
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double borderWidth;
  final Color? background;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.borderColor,
    this.borderWidth = 1,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? c.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: borderColor ?? c.border,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdAll,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Cabeçalho de seção: rótulo em caixa alta + contador.
class SectionHeader extends StatelessWidget {
  final String title;
  final int? count;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: c.textTertiary,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: AppRadius.smAll,
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

enum BannerTone { info, warning, danger }

/// Aviso contextual em bloco — usado para "entregas sem localização",
/// "estimativa offline" e afins.
class InfoBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final BannerTone tone;

  const InfoBanner({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.tone = BannerTone.info,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final accent = switch (tone) {
      BannerTone.info => c.textSecondary,
      BannerTone.warning => c.warning,
      BannerTone.danger => c.danger,
    };

    final background = switch (tone) {
      BannerTone.info => c.surfaceAlt,
      BannerTone.warning => c.warning.withValues(alpha: 0.12),
      BannerTone.danger => c.danger.withValues(alpha: 0.10),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.mdAll,
        border: tone == BannerTone.info
            ? null
            : Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                    height: 1.3,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    message!,
                    style: TextStyle(
                      fontSize: 12.8,
                      color: c.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta pequena e arredondada.
class AppChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool filled;

  const AppChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon != null ? 8 : 9,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: AppRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: filled ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }
}
