import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../../../stops/domain/entities/delivery_stop.dart';
import '../entities/active_route.dart';
import '../entities/route_option.dart';
import '../entities/route_plan.dart';
import '../entities/recalculation_result.dart';

abstract class RoutingRepository {
  /// Calcula uma alternativa por estratégia, todas a partir de [origin].
  ///
  /// Só entram paradas roteáveis (com coordenada válida) e pendentes — o que
  /// já foi entregue não deve reaparecer no roteiro.
  ///
  /// Se houver mais paradas do que o plano permite por rota, entram as mais
  /// próximas de [origin] e o resto volta em `RoutePlan.deferredStops`.
  Future<Either<Failure, RoutePlan>> calculateOptions({
    required GeoPoint origin,
    required List<DeliveryStop> stops,
  });

  /// Grava a rota escolhida como "em andamento". A partir daí ela sobrevive ao
  /// app ser fechado ou morto pelo sistema.
  Future<Either<Failure, ActiveRoute>> startRoute({
    required RouteOption option,
    required GeoPoint origin,
  });

  /// A rota em andamento, com as paradas no estado atual. Null se não houver.
  Future<Either<Failure, ActiveRoute?>> getActiveRoute();

  /// Reordena o que **falta** a partir de [origin], mantendo as entregas já
  /// feitas no lugar.
  ///
  /// A ordem original foi calculada de onde o dia começou. Depois de algumas
  /// entregas o entregador está longe daquele ponto, e a sequência que era
  /// ótima deixou de ser. Preservar as concluídas é intencional: o progresso
  /// do dia ("5 de 8") é o que dá sensação de avanço, e reiniciar em "0 de 3"
  /// apagaria isso.
  Future<Either<Failure, RecalculationResult>> recalculateFrom({
    required ActiveRoute route,
    required GeoPoint origin,
  });

  Future<Either<Failure, void>> finishRoute();
}
