import 'package:equatable/equatable.dart';

import '../../domain/entities/delivery_stop.dart';

abstract class StopsState extends Equatable {
  const StopsState();

  @override
  List<Object?> get props => [];
}

class StopsInitial extends StopsState {
  const StopsInitial();
}

class StopsLoading extends StopsState {
  const StopsLoading();
}

class StopsLoaded extends StopsState {
  final List<DeliveryStop> stops;

  /// Ação em andamento sobre a lista já carregada (salvar, apagar, resolver
  /// coordenadas). Mantém a lista na tela em vez de piscar um spinner.
  final bool isBusy;

  const StopsLoaded(this.stops, {this.isBusy = false});

  List<DeliveryStop> get pending =>
      stops.where((s) => s.status == StopStatus.pending).toList();

  List<DeliveryStop> get completed =>
      stops.where((s) => s.status != StopStatus.pending).toList();

  /// As que entram no cálculo da rota.
  List<DeliveryStop> get routable =>
      pending.where((s) => s.isRoutable).toList();

  /// Pendentes sem coordenada — cadastradas offline ou com endereço que o
  /// geocoding não achou. A UI destaca essas para o usuário corrigir.
  List<DeliveryStop> get unresolved =>
      pending.where((s) => !s.isRoutable).toList();

  bool get canCalculateRoute => routable.isNotEmpty;

  StopsLoaded copyWith({List<DeliveryStop>? stops, bool? isBusy}) =>
      StopsLoaded(stops ?? this.stops, isBusy: isBusy ?? this.isBusy);

  @override
  List<Object?> get props => [stops, isBusy];
}

class StopsFailure extends StopsState {
  final String message;

  const StopsFailure(this.message);

  @override
  List<Object?> get props => [message];
}
