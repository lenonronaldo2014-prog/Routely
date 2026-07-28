import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';

abstract class LocationRepository {
  /// Posição atual do usuário, pedindo permissão se ainda não tiver.
  Future<Either<Failure, GeoPoint>> getCurrentLocation();

  /// Abre as configurações do app, para o caso de permissão negada
  /// permanentemente — é o único caminho de volta nesse estado.
  Future<void> openAppSettings();
}
