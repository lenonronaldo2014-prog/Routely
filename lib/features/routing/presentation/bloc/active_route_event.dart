import 'package:equatable/equatable.dart';

import '../../../../core/geo/geo_point.dart';
import '../../domain/entities/route_option.dart';

abstract class ActiveRouteEvent extends Equatable {
  const ActiveRouteEvent();

  @override
  List<Object?> get props => [];
}

/// Disparado na abertura do app e sempre que a lista de entregas muda — é o
/// que mantém o progresso da rota em dia.
class ActiveRouteLoadRequested extends ActiveRouteEvent {
  const ActiveRouteLoadRequested();
}

class ActiveRouteStartRequested extends ActiveRouteEvent {
  final RouteOption option;
  final GeoPoint origin;

  const ActiveRouteStartRequested({required this.option, required this.origin});

  @override
  List<Object?> get props => [option, origin];
}

/// Reordena o que falta a partir da posição atual.
class ActiveRouteRecalculateRequested extends ActiveRouteEvent {
  const ActiveRouteRecalculateRequested();
}

/// Verifica em silêncio se a ordem atual ainda faz sentido de onde o
/// entregador está. Se não fizer, a tela sugere recalcular.
class ActiveRouteDriftCheckRequested extends ActiveRouteEvent {
  const ActiveRouteDriftCheckRequested();
}

class ActiveRouteFinishRequested extends ActiveRouteEvent {
  const ActiveRouteFinishRequested();
}
