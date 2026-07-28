import 'package:equatable/equatable.dart';

import '../../../../core/geo/geo_point.dart';

/// De onde o endereço veio. A UI usa isso para ser honesta com o usuário —
/// "preenchido pela base offline" e "só identificamos o estado" são situações
/// bem diferentes e não podem parecer a mesma coisa.
enum AddressSource {
  /// Base de CEP instalada no aparelho. Funciona sem rede.
  localDirectory,

  /// CEP já consultado antes neste aparelho.
  cache,

  /// Consulta online (ViaCEP).
  network,

  /// Nada foi encontrado; só a UF, deduzida da faixa numérica do CEP.
  cepRange;

  bool get isOffline =>
      this == AddressSource.localDirectory ||
      this == AddressSource.cache ||
      this == AddressSource.cepRange;

  /// Resultado incompleto — o usuário ainda precisa digitar o logradouro.
  bool get isPartial => this == AddressSource.cepRange;
}

/// Resultado da consulta de CEP: tudo do endereço menos o número, que só o
/// usuário sabe.
class AddressLookup extends Equatable {
  final String cep;
  final String street;
  final String neighborhood;
  final String city;
  final String state;

  /// Vem preenchida quando a base local traz o centroide do CEP. É o que
  /// dispensa o geocoding online — de graça e sem rede.
  final GeoPoint? coordinate;

  final AddressSource source;

  const AddressLookup({
    required this.cep,
    required this.street,
    required this.neighborhood,
    required this.city,
    required this.state,
    required this.source,
    this.coordinate,
  });

  bool get hasCoordinate => coordinate?.isValid ?? false;

  /// CEPs de logradouro único (cidades pequenas) voltam sem rua. Nesse caso o
  /// usuário precisa digitar o logradouro na mão.
  bool get hasStreet => street.trim().isNotEmpty;

  bool get hasCity => city.trim().isNotEmpty;

  AddressLookup copyWith({AddressSource? source}) => AddressLookup(
        cep: cep,
        street: street,
        neighborhood: neighborhood,
        city: city,
        state: state,
        coordinate: coordinate,
        source: source ?? this.source,
      );

  @override
  List<Object?> get props =>
      [cep, street, neighborhood, city, state, coordinate, source];
}
