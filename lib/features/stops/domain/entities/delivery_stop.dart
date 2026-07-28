import 'package:equatable/equatable.dart';

import '../../../../core/geo/geo_point.dart';

enum StopStatus {
  pending,
  delivered,
  failed;

  static StopStatus fromName(String value) => StopStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => StopStatus.pending,
      );
}

/// Uma parada de entrega.
///
/// [coordinate] é nulo enquanto o endereço ainda não foi geocodificado — isso
/// acontece quando o usuário cadastra offline. A parada existe e é editável
/// nesse estado, mas não entra no cálculo de rota até ter coordenada.
class DeliveryStop extends Equatable {
  final String id;
  final String? label;
  final String street;
  final String? number;
  final String? complement;
  final String? neighborhood;
  final String? city;
  final String? state;
  final String? cep;
  final GeoPoint? coordinate;
  final String? notes;
  final StopStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;

  const DeliveryStop({
    required this.id,
    this.label,
    required this.street,
    this.number,
    this.complement,
    this.neighborhood,
    this.city,
    this.state,
    this.cep,
    this.coordinate,
    this.notes,
    this.status = StopStatus.pending,
    required this.createdAt,
    this.completedAt,
  });

  bool get isRoutable => coordinate != null && coordinate!.isValid;

  bool get isPending => status == StopStatus.pending;

  /// Linha principal mostrada na lista: "Rua das Flores, 123".
  String get shortAddress {
    final buffer = StringBuffer(street);
    if (number != null && number!.isNotEmpty) buffer.write(', $number');
    return buffer.toString();
  }

  /// Linha secundária: "Centro · Campinas/SP".
  String get locality {
    final parts = <String>[
      if (neighborhood != null && neighborhood!.isNotEmpty) neighborhood!,
      if (city != null && city!.isNotEmpty)
        state != null && state!.isNotEmpty ? '$city/$state' : city!,
    ];
    return parts.join(' · ');
  }

  /// Endereço completo, usado para geocoding e para o deep link de navegação.
  String get fullAddress {
    final parts = <String>[
      shortAddress,
      if (neighborhood != null && neighborhood!.isNotEmpty) neighborhood!,
      if (city != null && city!.isNotEmpty) city!,
      if (state != null && state!.isNotEmpty) state!,
      if (cep != null && cep!.isNotEmpty) cep!,
      'Brasil',
    ];
    return parts.join(', ');
  }

  DeliveryStop copyWith({
    String? label,
    String? street,
    String? number,
    String? complement,
    String? neighborhood,
    String? city,
    String? state,
    String? cep,
    GeoPoint? coordinate,
    String? notes,
    StopStatus? status,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return DeliveryStop(
      id: id,
      label: label ?? this.label,
      street: street ?? this.street,
      number: number ?? this.number,
      complement: complement ?? this.complement,
      neighborhood: neighborhood ?? this.neighborhood,
      city: city ?? this.city,
      state: state ?? this.state,
      cep: cep ?? this.cep,
      coordinate: coordinate ?? this.coordinate,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }

  @override
  List<Object?> get props => [
        id,
        label,
        street,
        number,
        complement,
        neighborhood,
        city,
        state,
        cep,
        coordinate,
        notes,
        status,
        createdAt,
        completedAt,
      ];
}
