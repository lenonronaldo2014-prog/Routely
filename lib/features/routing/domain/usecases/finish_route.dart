import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/routing_repository.dart';

class FinishRoute implements UseCase<void, NoParams> {
  final RoutingRepository repository;

  FinishRoute(this.repository);

  @override
  Future<Either<Failure, void>> call(NoParams params) {
    return repository.finishRoute();
  }
}
