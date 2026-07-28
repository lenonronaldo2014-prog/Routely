import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_spacing.dart';

/// Centraliza o conteúdo e limita a largura em telas grandes.
///
/// Sem isso, num tablet ou celular em paisagem cada linha de texto atravessa a
/// tela inteira e o formulário vira uma faixa desconfortável de ler.
///
/// A centralização é feita com **padding**, não com `Align` + `ConstrainedBox`.
/// Parece equivalente, mas não é: aquele par afrouxa as constraints que chegam
/// ao filho, e um `ListView` embaixo disso perde a altura definida e não
/// desenha nada. Padding preserva as constraints do pai — o filho continua
/// recebendo a altura real da tela.
class ResponsiveBody extends StatelessWidget {
  final Widget child;

  /// Listas e cards podem respirar mais que formulários.
  final bool wide;

  /// Substitui completamente o padding calculado, quando o chamador precisa
  /// controlar o espaçamento (ex.: lista que rola até a borda).
  final EdgeInsets? padding;

  const ResponsiveBody({
    super.key,
    required this.child,
    this.wide = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? horizontalInsets(context, wide: wide),
      child: child,
    );
  }

  /// Margem lateral que, além do respiro normal da tela, absorve o excedente
  /// quando a tela é mais larga que a largura máxima de leitura.
  static EdgeInsets horizontalInsets(
    BuildContext context, {
    bool wide = false,
  }) {
    final maxWidth = wide
        ? AppBreakpoints.maxWideContentWidth
        : AppBreakpoints.maxContentWidth;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final base = AppSpacing.screenPadding(context);
    final overflow = ((screenWidth - maxWidth) / 2).clamp(0.0, double.infinity);

    return EdgeInsets.symmetric(horizontal: base + overflow);
  }
}

/// Mesma ideia da [ResponsiveBody], para barras de ação fixas no rodapé.
class ResponsiveActionBar extends StatelessWidget {
  final Widget child;
  final bool wide;

  const ResponsiveActionBar({
    super.key,
    required this.child,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final insets = ResponsiveBody.horizontalInsets(context, wide: wide);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          insets.left,
          AppSpacing.xs,
          insets.right,
          AppSpacing.sm,
        ),
        child: child,
      ),
    );
  }
}
