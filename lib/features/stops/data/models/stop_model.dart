import '../../../../core/geo/geo_point.dart';
import '../../domain/entities/delivery_stop.dart';

class StopModel extends DeliveryStop {
  const StopModel({
    required super.id,
    super.label,
    required super.street,
    super.number,
    super.complement,
    super.neighborhood,
    super.city,
    super.state,
    super.cep,
    super.coordinate,
    super.notes,
    super.status,
    required super.createdAt,
    super.completedAt,
  });

  factory StopModel.fromEntity(DeliveryStop stop) => StopModel(
        id: stop.id,
        label: stop.label,
        street: stop.street,
        number: stop.number,
        complement: stop.complement,
        neighborhood: stop.neighborhood,
        city: stop.city,
        state: stop.state,
        cep: stop.cep,
        coordinate: stop.coordinate,
        notes: stop.notes,
        status: stop.status,
        createdAt: stop.createdAt,
        completedAt: stop.completedAt,
      );

  factory StopModel.fromMap(Map<String, dynamic> map) {
    final lat = map['latitude'] as double?;
    final lng = map['longitude'] as double?;

    return StopModel(
      id: map['id'] as String,
      label: map['label'] as String?,
      street: map['street'] as String,
      number: map['number'] as String?,
      complement: map['complement'] as String?,
      neighborhood: map['neighborhood'] as String?,
      city: map['city'] as String?,
      state: map['state'] as String?,
      cep: map['cep'] as String?,
      coordinate: (lat != null && lng != null)
          ? GeoPoint(latitude: lat, longitude: lng)
          : null,
      notes: map['notes'] as String?,
      status: StopStatus.fromName(map['status'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      completedAt: map['completed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'street': street,
        'number': number,
        'complement': complement,
        'neighborhood': neighborhood,
        'city': city,
        'state': state,
        'cep': cep,
        'latitude': coordinate?.latitude,
        'longitude': coordinate?.longitude,
        'notes': notes,
        'status': status.name,
        'created_at': createdAt.millisecondsSinceEpoch,
        'completed_at': completedAt?.millisecondsSinceEpoch,
      };
}
