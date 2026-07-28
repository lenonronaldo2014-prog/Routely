import 'package:equatable/equatable.dart';

import '../../../../core/geo/geo_point.dart';
import '../../domain/entities/delivery_stop.dart';

abstract class StopFormEvent extends Equatable {
  const StopFormEvent();

  @override
  List<Object?> get props => [];
}

/// Abre o formulário — em branco, ou preenchido para edição.
class StopFormStarted extends StopFormEvent {
  final DeliveryStop? existing;

  const StopFormStarted({this.existing});

  @override
  List<Object?> get props => [existing];
}

class CepLookupRequested extends StopFormEvent {
  final String cep;

  const CepLookupRequested(this.cep);

  @override
  List<Object?> get props => [cep];
}

/// O usuário posicionou o pino no mapa. Essa coordenada passa a valer mais que
/// qualquer geocoding: ele está olhando para a porta, o serviço não.
class StopLocationPicked extends StopFormEvent {
  final GeoPoint coordinate;

  const StopLocationPicked(this.coordinate);

  @override
  List<Object?> get props => [coordinate];
}

class StopFormSubmitted extends StopFormEvent {
  final String? label;
  final String street;
  final String? number;
  final String? complement;
  final String? neighborhood;
  final String? city;
  final String? state;
  final String? cep;
  final String? notes;

  const StopFormSubmitted({
    this.label,
    required this.street,
    this.number,
    this.complement,
    this.neighborhood,
    this.city,
    this.state,
    this.cep,
    this.notes,
  });

  @override
  List<Object?> get props => [
        label,
        street,
        number,
        complement,
        neighborhood,
        city,
        state,
        cep,
        notes,
      ];
}
