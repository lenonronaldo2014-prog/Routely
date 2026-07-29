import 'package:equatable/equatable.dart';

import '../../../../core/geo/geo_point.dart';
import '../../domain/entities/address_suggestion.dart';
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

/// O usuário digitou no campo de rua.
///
/// Não dispara consulta na hora: o bloc espera ele parar de digitar. Uma
/// chamada por tecla queimaria a cota do dia em poucos endereços.
class AddressTextChanged extends StopFormEvent {
  final String text;

  const AddressTextChanged(this.text);

  @override
  List<Object?> get props => [text];
}

/// Disparado pelo próprio bloc quando a digitação parou. Só isso vira consulta.
class AddressSuggestionsRequested extends StopFormEvent {
  final String text;

  const AddressSuggestionsRequested(this.text);

  @override
  List<Object?> get props => [text];
}

/// O usuário escolheu uma sugestão.
///
/// A sugestão veio com coordenada, então o endereço já está localizado — não
/// há segunda consulta para descobrir o que a primeira já respondeu.
class AddressSuggestionSelected extends StopFormEvent {
  final AddressSuggestion suggestion;

  const AddressSuggestionSelected(this.suggestion);

  @override
  List<Object?> get props => [suggestion];
}

/// Fecha a lista de sugestões sem escolher nenhuma.
class AddressSuggestionsDismissed extends StopFormEvent {
  const AddressSuggestionsDismissed();
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
