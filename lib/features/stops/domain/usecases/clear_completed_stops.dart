import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/stops_repository.dart';

class ClearCompletedStops implements UseCase<int, NoParams> {
  final StopsRepository repository;

  ClearCompletedStops(this.repository);

  @override
  Future<Either<Failure, int>> call(NoParams params) {
    return repository.clearCompleted();
  }
}
