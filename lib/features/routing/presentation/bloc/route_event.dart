import 'package:equatable/equatable.dart';

import '../../../stops/domain/entities/delivery_stop.dart';

abstract class RouteEvent extends Equatable {
  const RouteEvent();

  @override
  List<Object?> get props => [];
}

/// Pega a localização atual e calcula as alternativas a partir dela.
class RouteCalculationRequested extends RouteEvent {
  final List<DeliveryStop> stops;

  const RouteCalculationRequested(this.stops);

  @override
  List<Object?> get props => [stops];
}

class RouteCleared extends RouteEvent {
  const RouteCleared();
}
