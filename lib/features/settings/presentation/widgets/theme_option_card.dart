import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Cartão de escolha de tema com uma miniatura da própria interface.
///
/// Radio button com a palavra "Escuro" não mostra nada. A miniatura mostra —
/// o usuário vê o resultado antes de escolher, que é o ponto de um seletor de
/// aparência.
class ThemeOptionCard extends StatelessWidget {
  final String label;
  final bool isSelected;

  /// Paleta desenhada na miniatura. Nula na opção "Sistema", que renderiza
  /// as duas metades.
  final AppColors? preview;

  final VoidCallback onTap;

  const ThemeOptionCard({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Expanded(
      child: Semantics(
        label: label,
        selected: isSelected,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.mdAll,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: isSelected ? c.brandSoft : Colors.transparent,
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: isSelected ? c.brand : c.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 0.72,
                    child: ClipRRect(
                      borderRadius: AppRadius.smAll,
                      child: preview == null
                          ? const _SplitPreview()
                          : _MiniPreview(palette: preview!),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isSelected) ...[
                        Icon(Icons.check_circle_rounded,
                            size: 14, color: c.brand),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w600,
                            color:
                                isSelected ? c.textPrimary : c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Miniatura da tela de entregas na paleta indicada.
class _MiniPreview extends StatelessWidget {
  final AppColors palette;

  const _MiniPreview({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.surfaceSunken,
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bar(width: 34, height: 6, color: palette.textPrimary),
          const SizedBox(height: 3),
          _bar(width: 22, height: 3, color: palette.textTertiary),
          const SizedBox(height: 7),
          _card(),
          const SizedBox(height: 4),
          _card(),
          const Spacer(),
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: palette.brand,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card() {
    return Container(
      height: 17,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: palette.border, width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              border: Border.all(color: palette.borderStrong, width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(width: 26, height: 3.5, color: palette.textPrimary),
              const SizedBox(height: 2),
              _bar(width: 18, height: 2.5, color: palette.textTertiary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar({
    required double width,
    required double height,
    required Color color,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

/// Opção "Sistema": metade clara, metade escura, cortada na diagonal.
class _SplitPreview extends StatelessWidget {
  const _SplitPreview();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _MiniPreview(palette: AppColors.light),
        ClipPath(
          clipper: _DiagonalClipper(),
          child: const _MiniPreview(palette: AppColors.dark),
        ),
      ],
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
