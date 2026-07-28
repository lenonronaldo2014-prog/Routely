import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/active_route.dart';
import '../repositories/routing_repository.dart';

/// Carrega a rota em andamento na abertura do app. É o que permite retomar o
/// roteiro exatamente onde parou depois do celular morrer.
class GetActiveRoute implements UseCase<ActiveRoute?, NoParams> {
  final RoutingRepository repository;

  GetActiveRoute(this.repository);

  @override
  Future<Either<Failure, ActiveRoute?>> call(NoParams params) {
    return repository.getActiveRoute();
  }
}
