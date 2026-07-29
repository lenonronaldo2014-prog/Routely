import 'package:equatable/equatable.dart';

import '../../../../core/geo/geo_point.dart';
import 'address_query.dart';

/// Uma opção do autocomplete, já com a coordenada dentro.
///
/// A coordenada vir junto é o ponto principal: quando o usuário escolhe uma
/// sugestão, o endereço já está localizado. Pedir a coordenada numa segunda
/// consulta gastaria uma chamada para descobrir algo que a primeira já
/// respondeu — e é assim que se queima a cota do plano gratuito à toa.
class AddressSuggestion extends Equatable {
  /// Linha principal: rua e número.
  final String label;

  /// Linha de baixo: bairro, cidade, UF, CEP. Serve para o usuário distinguir
  /// duas ruas de mesmo nome em cidades diferentes — o que é comum.
  final String detail;

  /// Campos separados, para preencher o formulário inteiro de uma vez.
  final AddressQuery query;

  final GeoPoint point;
  final LocationPrecision precision;

  const AddressSuggestion({
    required this.label,
    required this.detail,
    required this.query,
    required this.point,
    required this.precision,
  });

  @override
  List<Object?> get props => [label, detail, query, point, precision];
}
