import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/delivery_stop.dart';
import '../repositories/stops_repository.dart';

/// Roda quando a rede volta, para preencher as coordenadas das paradas que
/// foram cadastradas offline.
class ResolvePendingCoordinates
    implements UseCase<List<DeliveryStop>, NoParams> {
  final StopsRepository repository;

  ResolvePendingCoordinates(this.repository);

  @override
  Future<Either<Failure, List<DeliveryStop>>> call(NoParams params) {
    return repository.resolvePendingCoordinates();
  }
}
