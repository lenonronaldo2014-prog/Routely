import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../stops/domain/entities/delivery_stop.dart';
import '../../domain/entities/active_route.dart';
import '../../domain/entities/recalculation_result.dart';
import '../../domain/entities/route_option.dart';
import '../../domain/entities/route_plan.dart';
import '../../domain/entities/route_strategy.dart';
import '../../domain/repositories/routing_repository.dart';
import '../../domain/repositories/travel_matrix_provider.dart';
import '../../domain/services/route_optimizer.dart';
import '../datasources/route_local_data_source.dart';

class RoutingRepositoryImpl implements RoutingRepository {
  final TravelMatrixProvider matrixProvider;
  final RouteOptimizer optimizer;
  final AppSettings settings;
  final RouteLocalDataSource localDataSource;

  RoutingRepositoryImpl({
    required this.matrixProvider,
    required this.optimizer,
    required this.settings,
    required this.localDataSource,
  });

  @override
  Future<Either<Failure, RoutePlan>> calculateOptions({
    required GeoPoint origin,
    required List<DeliveryStop> stops,
  }) async {
    final routable = stops.where((s) => s.isRoutable).toList();
    if (routable.isEmpty) return Left(EmptyRouteFailure());

    final tier = settings.planTier;
    final (batch, deferred) = _splitIntoBatch(
      stops: routable,
      origin: origin,
      limit: tier.maxStopsPerRoute,
    );

    final points = <GeoPoint>[origin, ...batch.map((s) => s.coordinate!)];

    final matrixResult = await matrixProvider.buildMatrix(points);

    return matrixResult.map((matrix) {
      // A matriz é calculada uma vez e reaproveitada pelas três estratégias —
      // é a parte cara quando o provider for um serviço externo cobrado por
      // elemento.
      final options = RouteStrategy.values
          .map((strategy) => optimizer.optimize(
                strategy: strategy,
                stops: batch,
                matrix: matrix,
                serviceTimePerStop: settings.serviceTimePerStop,
              ))
          .toList();

      return RoutePlan(
        // Duas estratégias podem convergir para a mesma ordem quando há poucas
        // paradas. Mostrar cards idênticos passa a impressão de que o app está
        // quebrado, então colapsamos as repetições.
        options: _dedupeByOrder(options),
        batchStops: batch,
        deferredStops: deferred,
        tier: tier,
      );
    });
  }

  /// Separa as [limit] paradas mais próximas de [origin]; o resto fica para o
  /// próximo grupo.
  ///
  /// O critério é distância em linha reta até a origem — não a ordem ótima do
  /// roteiro. É de propósito: pegar o "melhor subconjunto de 8" seria um
  /// problema de otimização bem mais caro, e na prática as mais próximas já
  /// formam um agrupamento geográfico coerente. Depois de entregá-las, o
  /// próximo cálculo parte de onde o entregador realmente está.
  (List<DeliveryStop>, List<DeliveryStop>) _splitIntoBatch({
    required List<DeliveryStop> stops,
    required GeoPoint origin,
    required int limit,
  }) {
    if (stops.length <= limit) return (stops, const []);

    final byDistance = [...stops]..sort((a, b) {
        final da = origin.haversineDistanceTo(a.coordinate!);
        final db = origin.haversineDistanceTo(b.coordinate!);
        return da.compareTo(db);
      });

    return (
      byDistance.take(limit).toList(),
      byDistance.skip(limit).toList(),
    );
  }

  @override
  Future<Either<Failure, ActiveRoute>> startRoute({
    required RouteOption option,
    required GeoPoint origin,
  }) async {
    final route = ActiveRoute.fromOption(
      option: option,
      origin: origin,
      startedAt: DateTime.now(),
    );

    try {
      await localDataSource.saveActiveRoute(route);
      return Right(route);
    } on CacheException {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, ActiveRoute?>> getActiveRoute() async {
    try {
      return Right(await localDataSource.getActiveRoute());
    } on CacheException {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, RecalculationResult>> recalculateFrom({
    required ActiveRoute route,
    required GeoPoint origin,
  }) async {
    final pending = route.remainingLegs
        .map((leg) => leg.to)
        .where((stop) => stop.isRoutable)
        .toList();

    if (pending.isEmpty) return Left(EmptyRouteFailure());

    final points = <GeoPoint>[origin, ...pending.map((s) => s.coordinate!)];
    final matrixResult = await matrixProvider.buildMatrix(points);

    if (matrixResult.isLeft()) {
      return Left(matrixResult.fold((f) => f, (_) => EmptyRouteFailure()));
    }

    final rebuilt = matrixResult.map((matrix) {
      // Mantém a estratégia que o usuário escolheu no começo: ele decidiu
      // "mais econômica" por um motivo, e recalcular não é hora de mudar isso
      // por conta própria.
      final reordered = optimizer.optimize(
        strategy: route.strategy,
        stops: pending,
        matrix: matrix,
        serviceTimePerStop: settings.serviceTimePerStop,
      );

      // Quanto ele rodaria seguindo a ordem antiga a partir daqui. `pending`
      // está na ordem original, e a matriz foi montada nessa mesma sequência —
      // então o caminho antigo é simplesmente 0→1→2→…→N.
      var oldOrderDistance = 0.0;
      for (var i = 0; i < pending.length; i++) {
        oldOrderDistance += matrix.distanceBetween(i, i + 1);
      }
      final saved = oldOrderDistance - reordered.totalDistanceMeters;

      final done = route.legs
          .where((leg) => leg.to.status != StopStatus.pending)
          .toList();

      final doneTravel =
          done.fold(0.0, (sum, leg) => sum + leg.durationSeconds);
      final doneDistance =
          done.fold(0.0, (sum, leg) => sum + leg.distanceMeters);

      return RecalculationResult(
        savedDistanceMeters: saved,
        route: ActiveRoute(
          strategy: route.strategy,
          // A origem passa a ser onde o entregador está agora — é dela que os
          // trechos restantes foram medidos.
          origin: origin,
          legs: [...done, ...reordered.legs],
          travelDurationSeconds: doneTravel + reordered.travelDurationSeconds,
          // Tempo de parada é por entrega, então vale para o roteiro inteiro.
          serviceDurationSeconds:
              (done.length + reordered.legs.length) *
                  settings.serviceTimePerStop.inSeconds.toDouble(),
          totalDistanceMeters: doneDistance + reordered.totalDistanceMeters,
          isEstimate: matrix.isEstimate,
          // Preserva o início: é o horário em que o dia começou, não o do
          // recálculo.
          startedAt: route.startedAt,
        ),
      );
    });

    final result = rebuilt.getOrElse(
      () => RecalculationResult(route: route, savedDistanceMeters: 0),
    );

    try {
      await localDataSource.saveActiveRoute(result.route);
      return Right(result);
    } on CacheException {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> finishRoute() async {
    try {
      await localDataSource.clearActiveRoute();
      return const Right(null);
    } on CacheException {
      return Left(CacheFailure());
    }
  }

  List<RouteOption> _dedupeByOrder(List<RouteOption> options) {
    final seen = <String>{};
    final unique = <RouteOption>[];

    for (final option in options) {
      final key = option.orderedStops.map((s) => s.id).join('>');
      if (seen.add(key)) unique.add(option);
    }

    return unique;
  }
}
