import 'package:equatable/equatable.dart';

import 'active_route.dart';

/// Resultado de um recálculo, com o ganho medido.
///
/// A economia precisa ser explicada porque o número total **sobe** depois de
/// recalcular, e isso confunde: o total antigo era medido de onde o dia
/// começou; o novo, de onde o entregador está agora. Comparar os dois é
/// comparar coisas diferentes.
///
/// A comparação honesta é: quanto ele rodaria seguindo a ordem antiga **a
/// partir daqui** contra quanto vai rodar na ordem nova. É isso que
/// [savedDistanceMeters] mede.
class RecalculationResult extends Equatable {
  final ActiveRoute route;

  /// Quanto a ordem nova economiza em relação a seguir a antiga a partir da
  /// posição atual. Zero ou negativo quando a ordem antiga já era boa.
  final double savedDistanceMeters;

  const RecalculationResult({
    required this.route,
    required this.savedDistanceMeters,
  });

  /// Abaixo de 100m não vale anunciar economia — é ruído de arredondamento.
  bool get hasMeaningfulGain => savedDistanceMeters >= 100;

  @override
  List<Object?> get props => [route, savedDistanceMeters];
}
