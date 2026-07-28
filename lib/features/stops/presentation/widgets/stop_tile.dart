import 'package:flutter/material.dart';

import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/entities/delivery_stop.dart';

class StopTile extends StatelessWidget {
  final DeliveryStop stop;

  /// Número da parada dentro de uma rota. Nulo na lista solta, onde ainda não
  /// existe ordem definida.
  final int? sequence;

  final VoidCallback? onTap;
  final VoidCallback? onToggleDelivered;
  final VoidCallback? onDelete;

  /// Atalho para marcar a localização no mapa, direto da lista. Só aparece nas
  /// paradas sem coordenada — que são exatamente as que precisam de conserto.
  final VoidCallback? onFixLocation;

  const StopTile({
    super.key,
    required this.stop,
    this.sequence,
    this.onTap,
    this.onToggleDelivered,
    this.onDelete,
    this.onFixLocation,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDone = stop.status == StopStatus.delivered;
    final compact = AppBreakpoints.isCompact(context);

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
      background: isDone ? c.surfaceAlt : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _leading(context, isDone),
          SizedBox(width: compact ? AppSpacing.sm : AppSpacing.md - 2),
          Expanded(child: _details(context, isDone, compact)),
          if (onDelete != null)
            _IconAction(
              icon: Icons.close_rounded,
              tooltip: 'Remover entrega',
              onTap: onDelete!,
            ),
        ],
      ),
    );
  }

  Widget _leading(BuildContext context, bool isDone) {
    if (onToggleDelivered != null) {
      return _CheckButton(isDone: isDone, onTap: onToggleDelivered!);
    }

    final c = context.colors;

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.brand,
        borderRadius: AppRadius.smAll,
      ),
      child: Text(
        '${sequence ?? 0}',
        style: TextStyle(
          color: c.onBrand,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _details(BuildContext context, bool isDone, bool compact) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stop.label != null) ...[
          AppChip(label: stop.label!, color: c.accent),
          const SizedBox(height: AppSpacing.xs - 2),
        ],
        Text(
          stop.shortAddress,
          style: TextStyle(
            fontSize: compact ? 15 : 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            height: 1.25,
            color: isDone ? c.textTertiary : c.textPrimary,
            decoration: isDone ? TextDecoration.lineThrough : null,
            decorationColor: c.textTertiary,
          ),
        ),
        if (stop.locality.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            stop.locality,
            style: TextStyle(
              fontSize: 13,
              color: c.textSecondary,
              height: 1.3,
            ),
          ),
        ],
        if (stop.complement != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.meeting_room_outlined, size: 13, color: c.textTertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  stop.complement!,
                  style: TextStyle(fontSize: 12.5, color: c.textTertiary),
                ),
              ),
            ],
          ),
        ],
        if (stop.notes != null) ...[
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sticky_note_2_outlined, size: 13, color: c.textTertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  stop.notes!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: c.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (!stop.isRoutable && !isDone) ...[
          const SizedBox(height: AppSpacing.xs),
          if (onFixLocation == null)
            AppChip(
              label: 'Sem localização',
              icon: Icons.location_off_outlined,
              color: c.warning,
            )
          else
            _FixLocationButton(onTap: onFixLocation!),
        ],
      ],
    );
  }
}

/// Chip que também é botão: o aviso e a solução no mesmo lugar. Mostrar só o
/// problema e deixar o usuário procurar onde consertar é o que faz app parecer
/// burocrático.
class _FixLocationButton extends StatelessWidget {
  final VoidCallback onTap;

  const _FixLocationButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Material(
      color: c.warning.withValues(alpha: 0.14),
      borderRadius: AppRadius.smAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 14, color: c.warning),
              const SizedBox(width: 5),
              Text(
                'Marcar no mapa',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: c.warning,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckButton extends StatelessWidget {
  final bool isDone;
  final VoidCallback onTap;

  const _CheckButton({required this.isDone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Semantics(
      label: isDone ? 'Marcar como pendente' : 'Marcar como entregue',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          // Área de toque generosa: o usuário costuma estar de luva.
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isDone ? c.success : Colors.transparent,
                border: Border.all(
                  color: isDone ? c.success : c.borderStrong,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: isDone
                  ? const Icon(Icons.check_rounded, size: 19, color: Colors.white)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20, color: c.textTertiary),
          ),
        ),
      ),
    );
  }
}
