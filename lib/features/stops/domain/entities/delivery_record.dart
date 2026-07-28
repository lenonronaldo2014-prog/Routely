import 'package:equatable/equatable.dart';

import 'delivery_stop.dart';

/// Uma entrega já finalizada, arquivada.
///
/// Antes, "limpar concluídas" apagava. O entregador perdia o registro do
/// próprio dia de trabalho. Agora sai da lista ativa e vem para cá.
class DeliveryRecord extends Equatable {
  final String id;
  final String? label;
  final String street;
  final String? number;
  final String? neighborhood;
  final String? city;
  final String? state;
  final String? cep;
  final StopStatus status;
  final DateTime createdAt;
  final DateTime completedAt;

  /// Distância do trecho até esta parada, quando ela fazia parte de uma rota.
  /// É o que permite dizer quanto o dia rendeu em quilômetros.
  final double? distanceMeters;

  const DeliveryRecord({
    required this.id,
    this.label,
    required this.street,
    this.number,
    this.neighborhood,
    this.city,
    this.state,
    this.cep,
    required this.status,
    required this.createdAt,
    required this.completedAt,
    this.distanceMeters,
  });

  bool get wasDelivered => status == StopStatus.delivered;

  String get shortAddress {
    final buffer = StringBuffer(street);
    if (number != null && number!.isNotEmpty) buffer.write(', $number');
    return buffer.toString();
  }

  String get locality {
    final parts = <String>[
      if (neighborhood != null && neighborhood!.isNotEmpty) neighborhood!,
      if (city != null && city!.isNotEmpty)
        state != null && state!.isNotEmpty ? '$city/$state' : city!,
    ];
    return parts.join(' · ');
  }

  /// Data sem hora, para agrupar por dia.
  DateTime get day =>
      DateTime(completedAt.year, completedAt.month, completedAt.day);

  @override
  List<Object?> get props => [
        id,
        label,
        street,
        number,
        neighborhood,
        city,
        state,
        cep,
        status,
        createdAt,
        completedAt,
        distanceMeters,
      ];
}

/// Resumo de um dia de trabalho.
class DeliveryDay extends Equatable {
  final DateTime day;
  final List<DeliveryRecord> records;

  const DeliveryDay({required this.day, required this.records});

  int get delivered => records.where((r) => r.wasDelivered).length;

  int get failed => records.length - delivered;

  /// Só soma o que tem distância conhecida — entrega cadastrada e concluída
  /// fora de uma rota não tem trecho associado.
  double get distanceMeters => records.fold(
        0.0,
        (sum, r) => sum + (r.distanceMeters ?? 0),
      );

  bool get hasDistance => distanceMeters > 0;

  @override
  List<Object?> get props => [day, records];
}
