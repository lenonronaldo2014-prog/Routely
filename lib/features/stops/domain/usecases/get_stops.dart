import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/delivery_stop.dart';
import '../repositories/stops_repository.dart';

class GetStops implements UseCase<List<DeliveryStop>, NoParams> {
  final StopsRepository repository;

  GetStops(this.repository);

  @override
  Future<Either<Failure, List<DeliveryStop>>> call(NoParams params) {
    return repository.getStops();
  }
}
