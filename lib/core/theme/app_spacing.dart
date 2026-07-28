import 'package:flutter/widgets.dart';

import 'app_breakpoints.dart';

/// Escala de espaçamento em múltiplos de 4. Ter uma escala fechada é o que
/// impede o layout de virar uma coleção de números aleatórios (13, 17, 22…),
/// que é o principal motivo de uma tela parecer "quase certa" sem ninguém
/// saber dizer por quê.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Margem lateral da tela — cresce em telas maiores.
  static double screenPadding(BuildContext context) => AppBreakpoints.value(
        context,
        compact: md,
        medium: md,
        expanded: xl,
        large: xxl,
      );

  /// Espaço reservado embaixo para a barra de ação fixa não cobrir o conteúdo.
  static const double bottomActionInset = 104;
}

/// Raios de canto. Consistência aqui é metade da sensação de "acabado".
class AppRadius {
  AppRadius._();

  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
}
