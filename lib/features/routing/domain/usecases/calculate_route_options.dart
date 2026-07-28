import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../stops/domain/entities/delivery_stop.dart';
import '../entities/route_plan.dart';
import '../repositories/routing_repository.dart';

class CalculateRouteOptions
    implements UseCase<RoutePlan, CalculateRouteOptionsParams> {
  final RoutingRepository repository;

  CalculateRouteOptions(this.repository);

  @override
  Future<Either<Failure, RoutePlan>> call(
    CalculateRouteOptionsParams params,
  ) {
    return repository.calculateOptions(
      origin: params.origin,
      stops: params.stops,
    );
  }
}

class CalculateRouteOptionsParams extends Equatable {
  final GeoPoint origin;
  final List<DeliveryStop> stops;

  const CalculateRouteOptionsParams({
    required this.origin,
    required this.stops,
  });

  @override
  List<Object> get props => [origin, stops];
}
