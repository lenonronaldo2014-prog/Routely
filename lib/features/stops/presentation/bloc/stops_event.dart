import 'package:equatable/equatable.dart';

import '../../../../core/geo/geo_point.dart';
import '../../domain/entities/delivery_stop.dart';

abstract class StopsEvent extends Equatable {
  const StopsEvent();

  @override
  List<Object?> get props => [];
}

class StopsLoadRequested extends StopsEvent {
  const StopsLoadRequested();
}

class StopSaveRequested extends StopsEvent {
  final DeliveryStop stop;

  const StopSaveRequested(this.stop);

  @override
  List<Object?> get props => [stop];
}

class StopDeleteRequested extends StopsEvent {
  final String id;

  const StopDeleteRequested(this.id);

  @override
  List<Object?> get props => [id];
}

class StopStatusChangeRequested extends StopsEvent {
  final DeliveryStop stop;
  final StopStatus status;

  const StopStatusChangeRequested({required this.stop, required this.status});

  @override
  List<Object?> get props => [stop, status];
}

/// O usuário marcou a localização no mapa direto da lista, sem passar pelo
/// formulário. Caminho curto para consertar uma entrega que ficou sem ponto.
class StopLocationUpdateRequested extends StopsEvent {
  final DeliveryStop stop;
  final GeoPoint coordinate;

  const StopLocationUpdateRequested({
    required this.stop,
    required this.coordinate,
  });

  @override
  List<Object?> get props => [stop, coordinate];
}

class CompletedStopsClearRequested extends StopsEvent {
  const CompletedStopsClearRequested();
}

/// Tenta geocodificar as paradas cadastradas offline. Disparado quando a rede
/// volta ou quando o usuário puxa para atualizar.
class PendingCoordinatesResolveRequested extends StopsEvent {
  const PendingCoordinatesResolveRequested();
}
