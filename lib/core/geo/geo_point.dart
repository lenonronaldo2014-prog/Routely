import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// Coordenada geográfica. Fica no core (e não numa lib externa como latlong2)
/// para que a camada de domínio não dependa de pacote de terceiro.
class GeoPoint extends Equatable {
  final double latitude;
  final double longitude;

  const GeoPoint({required this.latitude, required this.longitude});

  static const double _earthRadiusMeters = 6371000.0;

  /// Distância em linha reta ("como o pássaro voa") até [other], em metros.
  double haversineDistanceTo(GeoPoint other) {
    final lat1 = _toRadians(latitude);
    final lat2 = _toRadians(other.latitude);
    final dLat = _toRadians(other.latitude - latitude);
    final dLon = _toRadians(other.longitude - longitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return _earthRadiusMeters * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;

  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      !(latitude == 0 && longitude == 0);

  @override
  List<Object> get props => [latitude, longitude];

  @override
  String toString() =>
      '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
}
