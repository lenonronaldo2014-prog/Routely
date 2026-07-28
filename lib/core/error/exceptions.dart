class ServerException implements Exception {
  final int? statusCode;
  final String? message;
  ServerException({this.statusCode, this.message});
}

class CacheException implements Exception {
  final String? message;
  CacheException({this.message});
}

class GeocodingException implements Exception {
  final String message;
  GeocodingException(this.message);
}

class LocationException implements Exception {
  final String message;
  LocationException(this.message);
}

/// Falha ao ler o texto da foto da etiqueta.
class ScanException implements Exception {
  final String message;
  ScanException(this.message);
}
