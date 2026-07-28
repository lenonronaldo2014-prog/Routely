import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  @override
  List<Object> get props => [];
}

class ServerFailure extends Failure {
  final int? statusCode;
  ServerFailure({this.statusCode});

  @override
  List<Object> get props => [statusCode ?? 0];
}

class CacheFailure extends Failure {}

class ConnectionFailure extends Failure {}

/// Endereço não pôde ser resolvido para coordenadas (CEP inválido, sem
/// cobertura na base local, ou geocoding falhou).
class GeocodingFailure extends Failure {
  final String message;
  GeocodingFailure([this.message = '']);

  @override
  List<Object> get props => [message];
}

/// GPS desligado, permissão negada, ou timeout ao obter a posição.
class LocationFailure extends Failure {
  final LocationFailureReason reason;
  LocationFailure(this.reason);

  @override
  List<Object> get props => [reason];
}

enum LocationFailureReason {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  unknown,
}

/// Não há paradas suficientes para montar uma rota.
class EmptyRouteFailure extends Failure {}

/// A foto foi tirada mas nada de endereço foi reconhecido nela.
class ScanFailure extends Failure {
  final String message;
  ScanFailure([this.message = '']);

  @override
  List<Object> get props => [message];
}
