import 'package:equatable/equatable.dart';

import '../../../../core/geo/geo_point.dart';
import '../../../../core/util/cep_formatter.dart';

/// Os campos do endereço, separados.
///
/// Existe porque localizar um endereço não é uma pergunta só: quando o número
/// não é encontrado, ainda dá para achar a rua; quando a rua não existe no
/// mapa, ainda dá para achar o bairro. Cada tentativa usa uma combinação
/// diferente desses campos, então eles precisam chegar separados em vez de já
/// colados numa string.
class AddressQuery extends Equatable {
  final String? cep;
  final String? street;
  final String? number;
  final String? neighborhood;
  final String? city;
  final String? state;

  const AddressQuery({
    this.cep,
    this.street,
    this.number,
    this.neighborhood,
    this.city,
    this.state,
  });

  String? get normalizedCep {
    final digits = CepFormatter.normalize(cep ?? '');
    return CepFormatter.isValid(digits) ? digits : null;
  }

  bool get hasStreet => (street ?? '').trim().isNotEmpty;
  bool get hasCity => (city ?? '').trim().isNotEmpty;
  bool get hasNeighborhood => (neighborhood ?? '').trim().isNotEmpty;

  /// Vazia demais para tentar qualquer coisa.
  bool get isEmpty => !hasStreet && !hasCity && normalizedCep == null;

  /// Endereço completo em texto, para a busca livre.
  String get fullText {
    final streetPart = hasStreet
        ? [street!.trim(), if ((number ?? '').trim().isNotEmpty) number!.trim()]
            .join(', ')
        : null;

    final parts = <String>[
      ?streetPart,
      if (hasNeighborhood) neighborhood!.trim(),
      if (hasCity) city!.trim(),
      if ((state ?? '').trim().isNotEmpty) state!.trim(),
      'Brasil',
    ];

    return parts.join(', ');
  }

  @override
  List<Object?> get props => [cep, street, number, neighborhood, city, state];
}

/// Quão perto do endereço real o ponto encontrado está.
///
/// A tela usa isso para dizer a verdade ao usuário. "Achei a rua, ajuste o
/// número" e "achei só a cidade" pedem esforços bem diferentes dele.
enum LocationPrecision {
  /// Endereço completo, com número.
  exact,

  /// A rua foi encontrada, mas não o número.
  street,

  /// Ponto do CEP.
  postalCode,

  /// Centro do bairro.
  neighborhood,

  /// Centro da cidade.
  city;

  /// Zoom que faz sentido para cada precisão. Abrir a cidade inteira em zoom
  /// de porta deixaria o usuário perdido num quarteirão qualquer.
  double get zoom => switch (this) {
        LocationPrecision.exact => 18,
        LocationPrecision.street => 17,
        LocationPrecision.postalCode => 17,
        LocationPrecision.neighborhood => 15,
        LocationPrecision.city => 13,
      };

  bool get needsAdjustment => this != LocationPrecision.exact;
}

class ApproximateLocation extends Equatable {
  final GeoPoint point;
  final LocationPrecision precision;

  const ApproximateLocation({required this.point, required this.precision});

  @override
  List<Object?> get props => [point, precision];
}
