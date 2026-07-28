import 'package:equatable/equatable.dart';

import '../../../../core/config/plan_limits.dart';
import '../../../stops/domain/entities/delivery_stop.dart';
import 'route_option.dart';

/// O resultado de um cálculo: as alternativas de rota para o **lote atual**,
/// mais o que ficou para depois.
///
/// Quando o usuário tem mais entregas do que o plano permite por rota, o app
/// não recusa nem trunca em silêncio: roteiriza as mais próximas da posição
/// atual e informa quantas sobraram. Terminado esse grupo, calcula de novo e
/// pega o próximo — que a essa altura será calculado a partir de onde ele
/// realmente parou, e não de onde começou o dia. Ou seja, fatiar não é só uma
/// limitação de plano: dá um roteiro mais preciso do que resolver 30 paradas
/// de uma vez com a origem defasada.
class RoutePlan extends Equatable {
  /// Uma alternativa por estratégia, todas cobrindo [batchStops].
  final List<RouteOption> options;

  /// As paradas que entraram nesta rota.
  final List<DeliveryStop> batchStops;

  /// As que ficaram para o próximo grupo, já ordenadas por proximidade.
  final List<DeliveryStop> deferredStops;

  final PlanTier tier;

  const RoutePlan({
    required this.options,
    required this.batchStops,
    required this.deferredStops,
    required this.tier,
  });

  bool get hasDeferred => deferredStops.isNotEmpty;

  int get deferredCount => deferredStops.length;

  int get totalStops => batchStops.length + deferredStops.length;

  /// Quantos grupos serão necessários para dar conta de tudo.
  int get totalBatches {
    final limit = tier.maxStopsPerRoute;
    if (limit <= 0) return 1;
    return (totalStops / limit).ceil();
  }

  @override
  List<Object?> get props => [options, batchStops, deferredStops, tier];
}
