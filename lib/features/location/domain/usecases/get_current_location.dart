import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/location_repository.dart';

class GetCurrentLocation implements UseCase<GeoPoint, NoParams> {
  final LocationRepository repository;

  GetCurrentLocation(this.repository);

  @override
  Future<Either<Failure, GeoPoint>> call(NoParams params) {
    return repository.getCurrentLocation();
  }
}
