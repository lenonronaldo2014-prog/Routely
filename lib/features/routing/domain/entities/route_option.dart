import 'package:equatable/equatable.dart';

import '../../../stops/domain/entities/delivery_stop.dart';
import 'route_strategy.dart';

/// Um trecho entre dois pontos consecutivos da rota.
class RouteLeg extends Equatable {
  /// Nulo no primeiro trecho, que parte da localização atual do usuário.
  final DeliveryStop? from;
  final DeliveryStop to;
  final double distanceMeters;
  final double durationSeconds;

  const RouteLeg({
    this.from,
    required this.to,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  @override
  List<Object?> get props => [from, to, distanceMeters, durationSeconds];
}

/// Uma alternativa de rota completa, pronta para o usuário comparar.
class RouteOption extends Equatable {
  final RouteStrategy strategy;
  final List<RouteLeg> legs;

  /// Tempo só de deslocamento, sem contar as paradas.
  final double travelDurationSeconds;

  /// Tempo somado das paradas (estacionar, achar o cliente, entregar).
  /// Ignorar isso é o motivo nº 1 de estimativa de rota ficar otimista demais.
  final double serviceDurationSeconds;

  final double totalDistanceMeters;

  /// `true` quando os tempos vieram de estimativa local, sem rede.
  final bool isEstimate;

  const RouteOption({
    required this.strategy,
    required this.legs,
    required this.travelDurationSeconds,
    required this.serviceDurationSeconds,
    required this.totalDistanceMeters,
    required this.isEstimate,
  });

  double get totalDurationSeconds =>
      travelDurationSeconds + serviceDurationSeconds;

  List<DeliveryStop> get orderedStops => legs.map((l) => l.to).toList();

  int get stopCount => legs.length;

  /// "1h 25min" / "45min"
  String get formattedDuration => formatDuration(totalDurationSeconds);

  String get formattedTravelDuration => formatDuration(travelDurationSeconds);

  /// "12,4 km" / "850 m"
  String get formattedDistance => formatDistance(totalDistanceMeters);

  /// Públicos porque a rota em andamento formata o que *falta*, não o total.
  static String formatDuration(double seconds) {
    final totalMinutes = (seconds / 60).round();
    if (totalMinutes < 60) return '${totalMinutes}min';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}min';
  }

  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    final km = meters / 1000;
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  @override
  List<Object> get props => [
        strategy,
        legs,
        travelDurationSeconds,
        serviceDurationSeconds,
        totalDistanceMeters,
        isEstimate,
      ];
}
