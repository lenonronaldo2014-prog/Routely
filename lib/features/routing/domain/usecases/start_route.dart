import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/active_route.dart';
import '../entities/route_option.dart';
import '../repositories/routing_repository.dart';

class StartRoute implements UseCase<ActiveRoute, StartRouteParams> {
  final RoutingRepository repository;

  StartRoute(this.repository);

  @override
  Future<Either<Failure, ActiveRoute>> call(StartRouteParams params) {
    return repository.startRoute(option: params.option, origin: params.origin);
  }
}

class StartRouteParams extends Equatable {
  final RouteOption option;
  final GeoPoint origin;

  const StartRouteParams({required this.option, required this.origin});

  @override
  List<Object> get props => [option, origin];
}
