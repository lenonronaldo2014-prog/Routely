import 'package:flutter/widgets.dart';

enum ScreenSize {
  /// Celular pequeno / antigo. Ainda muito comum entre entregadores.
  compact,

  /// Celular normal.
  medium,

  /// Celular grande em paisagem, tablet pequeno.
  expanded,

  /// Tablet.
  large,
}

/// Larguras de referência do Material 3, com um degrau extra embaixo para os
/// aparelhos de 360dp que ainda dominam a base Android no Brasil.
class AppBreakpoints {
  AppBreakpoints._();

  static const double compact = 360;
  static const double medium = 600;
  static const double expanded = 840;

  /// Largura máxima do conteúdo de leitura. Sem isso, num tablet o formulário
  /// estica de borda a borda e vira uma linha de texto de 900px — desconfortável
  /// de ler e feio.
  static const double maxContentWidth = 560;

  /// Rotas e listas podem respirar um pouco mais que formulários.
  static const double maxWideContentWidth = 720;

  static ScreenSize of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < compact) return ScreenSize.compact;
    if (width < medium) return ScreenSize.medium;
    if (width < expanded) return ScreenSize.expanded;
    return ScreenSize.large;
  }

  static bool isCompact(BuildContext context) =>
      of(context) == ScreenSize.compact;

  static bool isTabletLike(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= medium;

  /// Escolhe um valor conforme o tamanho da tela, caindo para o degrau
  /// anterior quando o específico não é informado.
  static T value<T>(
    BuildContext context, {
    required T compact,
    T? medium,
    T? expanded,
    T? large,
  }) {
    return switch (of(context)) {
      ScreenSize.compact => compact,
      ScreenSize.medium => medium ?? compact,
      ScreenSize.expanded => expanded ?? medium ?? compact,
      ScreenSize.large => large ?? expanded ?? medium ?? compact,
    };
  }
}
