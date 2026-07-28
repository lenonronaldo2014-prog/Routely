import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/active_route.dart';
import '../entities/recalculation_result.dart';
import '../repositories/routing_repository.dart';

/// Reordena o que falta a partir de onde o entregador está agora.
class RecalculateRoute
    implements UseCase<RecalculationResult, RecalculateRouteParams> {
  final RoutingRepository repository;

  RecalculateRoute(this.repository);

  @override
  Future<Either<Failure, RecalculationResult>> call(
    RecalculateRouteParams params,
  ) {
    return repository.recalculateFrom(
      route: params.route,
      origin: params.origin,
    );
  }
}

class RecalculateRouteParams extends Equatable {
  final ActiveRoute route;
  final GeoPoint origin;

  const RecalculateRouteParams({required this.route, required this.origin});

  @override
  List<Object> get props => [route, origin];
}
