import 'package:equatable/equatable.dart';

import '../../../../core/geo/geo_point.dart';
import '../../../stops/domain/entities/delivery_stop.dart';
import 'route_option.dart';
import 'route_strategy.dart';

/// A rota que o entregador escolheu e está executando.
///
/// Diferente de [RouteOption], que é uma alternativa efêmera mostrada para
/// comparação, esta é persistida: sobrevive ao app ser fechado, morto pelo
/// sistema ou ficar sem bateria. Perder a rota no meio de um roteiro de 20
/// entregas é o pior que pode acontecer com este app.
class ActiveRoute extends Equatable {
  final RouteStrategy strategy;

  /// De onde o roteiro foi calculado. Guardado para saber se o entregador já
  /// se afastou muito do ponto de partida — aí vale sugerir recalcular.
  final GeoPoint origin;

  final List<RouteLeg> legs;
  final double travelDurationSeconds;
  final double serviceDurationSeconds;
  final double totalDistanceMeters;
  final bool isEstimate;
  final DateTime startedAt;

  const ActiveRoute({
    required this.strategy,
    required this.origin,
    required this.legs,
    required this.travelDurationSeconds,
    required this.serviceDurationSeconds,
    required this.totalDistanceMeters,
    required this.isEstimate,
    required this.startedAt,
  });

  factory ActiveRoute.fromOption({
    required RouteOption option,
    required GeoPoint origin,
    required DateTime startedAt,
  }) {
    return ActiveRoute(
      strategy: option.strategy,
      origin: origin,
      legs: option.legs,
      travelDurationSeconds: option.travelDurationSeconds,
      serviceDurationSeconds: option.serviceDurationSeconds,
      totalDistanceMeters: option.totalDistanceMeters,
      isEstimate: option.isEstimate,
      startedAt: startedAt,
    );
  }

  List<DeliveryStop> get orderedStops => legs.map((l) => l.to).toList();

  int get totalStops => legs.length;

  int get deliveredCount =>
      legs.where((l) => l.to.status != StopStatus.pending).length;

  /// O que ainda falta, na ordem. É isso que a tela mostra em destaque.
  List<RouteLeg> get remainingLegs =>
      legs.where((l) => l.to.status == StopStatus.pending).toList();

  bool get isComplete => remainingLegs.isEmpty;

  double get progress => totalStops == 0 ? 0 : deliveredCount / totalStops;

  /// Próxima parada pendente, na ordem da rota.
  DeliveryStop? get nextStop =>
      remainingLegs.isEmpty ? null : remainingLegs.first.to;

  /// Tempo e distância do que ainda falta, não do roteiro inteiro. Depois de
  /// 5 de 8 entregas, "faltam 25min" é a informação útil; "2h no total" já não
  /// diz nada.
  double get remainingTravelSeconds =>
      remainingLegs.fold(0.0, (sum, l) => sum + l.durationSeconds);

  double get remainingDistanceMeters =>
      remainingLegs.fold(0.0, (sum, l) => sum + l.distanceMeters);

  double get remainingServiceSeconds => serviceDurationSeconds == 0
      ? 0
      : (serviceDurationSeconds / totalStops) * remainingLegs.length;

  double get remainingTotalSeconds =>
      remainingTravelSeconds + remainingServiceSeconds;

  String get formattedRemainingDuration =>
      RouteOption.formatDuration(remainingTotalSeconds);

  String get formattedRemainingDistance =>
      RouteOption.formatDistance(remainingDistanceMeters);

  /// Ganho mínimo para valer sugerir recálculo.
  ///
  /// Sem essa margem o app cutucaria o usuário a cada semáforo — qualquer
  /// deslocamento muda um pouco as distâncias. 300m é o ponto em que a
  /// diferença deixa de ser ruído e passa a valer o desvio.
  static const double _worthwhileGainMeters = 300;

  /// A rota foi montada a partir de um ponto que já ficou para trás. Se a
  /// parada mais próxima de onde o entregador está **agora** não é a próxima
  /// da fila, recalcular economiza caminho.
  bool wouldBenefitFromRecalculation(GeoPoint from) {
    final pending = remainingLegs
        .where((leg) => leg.to.isRoutable)
        .toList();

    // Com uma parada só não existe ordem para melhorar.
    if (pending.length < 2) return false;

    final next = pending.first.to;
    final distanceToNext = from.haversineDistanceTo(next.coordinate!);

    for (final leg in pending.skip(1)) {
      final distance = from.haversineDistanceTo(leg.to.coordinate!);
      if (distanceToNext - distance > _worthwhileGainMeters) return true;
    }

    return false;
  }

  /// Reconstrói a rota com as paradas atualizadas (status novo, endereço
  /// editado). Trechos cuja parada sumiu do banco são descartados.
  ActiveRoute withRefreshedStops(List<DeliveryStop> stops) {
    final byId = {for (final stop in stops) stop.id: stop};

    final refreshed = <RouteLeg>[];
    for (final leg in legs) {
      final updated = byId[leg.to.id];
      if (updated == null) continue;
      refreshed.add(RouteLeg(
        from: leg.from == null ? null : byId[leg.from!.id],
        to: updated,
        distanceMeters: leg.distanceMeters,
        durationSeconds: leg.durationSeconds,
      ));
    }

    return ActiveRoute(
      strategy: strategy,
      origin: origin,
      legs: refreshed,
      travelDurationSeconds: travelDurationSeconds,
      serviceDurationSeconds: serviceDurationSeconds,
      totalDistanceMeters: totalDistanceMeters,
      isEstimate: isEstimate,
      startedAt: startedAt,
    );
  }

  @override
  List<Object?> get props => [
        strategy,
        origin,
        legs,
        travelDurationSeconds,
        serviceDurationSeconds,
        totalDistanceMeters,
        isEstimate,
        startedAt,
      ];
}
