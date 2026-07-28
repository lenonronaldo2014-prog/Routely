import 'package:flutter_test/flutter_test.dart';
import 'package:routely/core/geo/geo_point.dart';
import 'package:routely/core/settings/app_settings.dart';
import 'package:routely/features/routing/data/providers/haversine_matrix_provider.dart';
import 'package:routely/features/routing/data/repositories/routing_repository_impl.dart';
import 'package:routely/features/routing/domain/entities/active_route.dart';
import 'package:routely/features/routing/domain/entities/recalculation_result.dart';
import 'package:routely/features/routing/domain/entities/route_option.dart';
import 'package:routely/features/routing/domain/entities/route_strategy.dart';
import 'package:routely/features/routing/domain/services/route_optimizer.dart';
import 'package:routely/features/stops/domain/entities/delivery_stop.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'route_local_data_source_test_stub.dart';

/// Onde o dia começou.
const _start = GeoPoint(latitude: -23.5505, longitude: -46.6333);

/// Parada a [kmNorth] km ao norte da origem — assim a geografia do teste é
/// previsível.
DeliveryStop _stop(
  String id,
  double kmNorth, {
  StopStatus status = StopStatus.pending,
}) =>
    DeliveryStop(
      id: id,
      street: 'Rua $id',
      coordinate: GeoPoint(
        latitude: _start.latitude - kmNorth * 0.009,
        longitude: _start.longitude,
      ),
      status: status,
      createdAt: DateTime(2026, 7, 1),
    );

ActiveRoute _routeOf(List<DeliveryStop> stops) {
  final legs = <RouteLeg>[];
  for (var i = 0; i < stops.length; i++) {
    legs.add(RouteLeg(
      from: i == 0 ? null : stops[i - 1],
      to: stops[i],
      distanceMeters: 1000,
      durationSeconds: 120,
    ));
  }

  return ActiveRoute(
    strategy: RouteStrategy.fastest,
    origin: _start,
    legs: legs,
    travelDurationSeconds: 120.0 * stops.length,
    serviceDurationSeconds: 180.0 * stops.length,
    totalDistanceMeters: 1000.0 * stops.length,
    isEstimate: true,
    startedAt: DateTime(2026, 7, 26, 8),
  );
}

void main() {
  late RoutingRepositoryImpl repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = RoutingRepositoryImpl(
      matrixProvider: const HaversineMatrixProvider(),
      optimizer: const RouteOptimizer(),
      settings: AppSettings(await SharedPreferences.getInstance()),
      localDataSource: NoopRouteLocalDataSource(),
    );
  });

  Future<RecalculationResult> recalculateFull(
    ActiveRoute route,
    GeoPoint from,
  ) async {
    final result =
        await repository.recalculateFrom(route: route, origin: from);
    return result.getOrElse(() => throw StateError('recálculo falhou'));
  }

  Future<ActiveRoute> recalculate(ActiveRoute route, GeoPoint from) async =>
      (await recalculateFull(route, from)).route;

  group('wouldBenefitFromRecalculation', () {
    test('não sugere quando a próxima já é a mais perto', () {
      final route = _routeOf([_stop('a', 1), _stop('b', 5), _stop('c', 10)]);

      expect(route.wouldBenefitFromRecalculation(_start), isFalse);
    });

    // O caso real: o entregador desviou e agora está do outro lado.
    test('sugere quando outra parada ficou mais perto', () {
      final route = _routeOf([_stop('a', 1), _stop('b', 5), _stop('c', 10)]);

      // Perto da parada 'c', longe da 'a'.
      final atFarEnd = GeoPoint(
        latitude: _start.latitude - 10 * 0.009,
        longitude: _start.longitude,
      );

      expect(route.wouldBenefitFromRecalculation(atFarEnd), isTrue);
    });

    // Sem margem o app cutucaria o usuário a cada semáforo.
    test('ignora diferença pequena', () {
      final route = _routeOf([_stop('a', 1), _stop('b', 1.1)]);

      expect(
        route.wouldBenefitFromRecalculation(_start),
        isFalse,
        reason: '100m de diferença é ruído, não desvio',
      );
    });

    test('não sugere com uma parada só restante', () {
      final route = _routeOf([
        _stop('a', 1, status: StopStatus.delivered),
        _stop('b', 5),
      ]);

      expect(route.wouldBenefitFromRecalculation(_start), isFalse);
    });

    test('ignora as já entregues na conta', () {
      final route = _routeOf([
        _stop('a', 1, status: StopStatus.delivered),
        _stop('b', 5),
        _stop('c', 10),
      ]);

      // Perto da 'a', que já foi entregue — não deveria influenciar.
      expect(route.wouldBenefitFromRecalculation(_start), isFalse);
    });
  });

  group('recalcular', () {
    test('reordena as pendentes a partir da posição atual', () async {
      final route = _routeOf([_stop('a', 1), _stop('b', 5), _stop('c', 10)]);

      // Entregador agora está no extremo oposto.
      final atFarEnd = GeoPoint(
        latitude: _start.latitude - 11 * 0.009,
        longitude: _start.longitude,
      );

      final updated = await recalculate(route, atFarEnd);

      expect(
        updated.orderedStops.map((s) => s.id),
        ['c', 'b', 'a'],
        reason: 'de onde ele está, a ordem inverte',
      );
    });

    // O ponto central: quem entregou 5 de 8 tem que continuar vendo "5 de 8".
    test('preserva as entregas já feitas e o progresso', () async {
      final route = _routeOf([
        _stop('a', 1, status: StopStatus.delivered),
        _stop('b', 2, status: StopStatus.delivered),
        _stop('c', 5),
        _stop('d', 10),
      ]);

      final updated = await recalculate(route, _start);

      expect(updated.totalStops, 4);
      expect(updated.deliveredCount, 2);
      expect(updated.remainingLegs, hasLength(2));
      expect(
        updated.orderedStops.take(2).map((s) => s.id),
        ['a', 'b'],
        reason: 'as entregues continuam no começo, na ordem original',
      );
    });

    test('mantém a estratégia escolhida pelo usuário', () async {
      final route = ActiveRoute(
        strategy: RouteStrategy.shortest,
        origin: _start,
        legs: [
          RouteLeg(
            to: _stop('a', 1),
            distanceMeters: 1000,
            durationSeconds: 120,
          ),
          RouteLeg(
            from: _stop('a', 1),
            to: _stop('b', 5),
            distanceMeters: 4000,
            durationSeconds: 480,
          ),
        ],
        travelDurationSeconds: 600,
        serviceDurationSeconds: 360,
        totalDistanceMeters: 5000,
        isEstimate: true,
        startedAt: DateTime(2026, 7, 26, 8),
      );

      final updated = await recalculate(route, _start);

      expect(updated.strategy, RouteStrategy.shortest);
    });

    test('preserva o horário de início do dia', () async {
      final route = _routeOf([_stop('a', 1), _stop('b', 5)]);

      final updated = await recalculate(route, _start);

      expect(updated.startedAt, DateTime(2026, 7, 26, 8));
    });

    test('a origem passa a ser a posição atual', () async {
      final route = _routeOf([_stop('a', 1), _stop('b', 5)]);
      const current = GeoPoint(latitude: -23.60, longitude: -46.70);

      final updated = await recalculate(route, current);

      expect(updated.origin, current);
    });

    test('o tempo de parada cobre o roteiro inteiro', () async {
      final route = _routeOf([
        _stop('a', 1, status: StopStatus.delivered),
        _stop('b', 5),
        _stop('c', 10),
      ]);

      final updated = await recalculate(route, _start);

      // 3 paradas × 3min padrão.
      expect(updated.serviceDurationSeconds, 3 * 180);
    });

    test('as distâncias restantes são medidas da posição nova', () async {
      final route = _routeOf([_stop('a', 1), _stop('b', 5)]);
      final atFarEnd = GeoPoint(
        latitude: _start.latitude - 5 * 0.009,
        longitude: _start.longitude,
      );

      final updated = await recalculate(route, atFarEnd);

      // Estando em cima da 'b', o primeiro trecho é praticamente zero.
      expect(updated.legs.first.distanceMeters, lessThan(200));
      expect(updated.legs.first.to.id, 'b');
    });

    // O total mostrado na tela SOBE depois de recalcular, porque o número
    // antigo era medido de onde o dia começou. Sem esse cálculo o usuário
    // olha "26min → 28min" e conclui que piorou.
    test('mede a economia contra seguir a ordem antiga daqui', () async {
      final route = _routeOf([_stop('a', 1), _stop('b', 5), _stop('c', 10)]);

      // No extremo oposto: a ordem antiga mandaria voltar tudo.
      final atFarEnd = GeoPoint(
        latitude: _start.latitude - 11 * 0.009,
        longitude: _start.longitude,
      );

      final result = await recalculateFull(route, atFarEnd);

      expect(result.savedDistanceMeters, greaterThan(0));
      expect(result.hasMeaningfulGain, isTrue);
    });

    test('não anuncia ganho quando a ordem antiga já era boa', () async {
      final route = _routeOf([_stop('a', 1), _stop('b', 5), _stop('c', 10)]);

      // De onde o dia começou, a ordem original continua sendo a melhor.
      final result = await recalculateFull(route, _start);

      expect(result.savedDistanceMeters, lessThan(100));
      expect(result.hasMeaningfulGain, isFalse);
    });

    test('a economia bate com a diferença real de percurso', () async {
      final route = _routeOf([_stop('a', 1), _stop('b', 9)]);

      // Em cima da parada 'b'. Ordem antiga: b→a→b. Nova: b→a.
      final atB = GeoPoint(
        latitude: _start.latitude - 9 * 0.009,
        longitude: _start.longitude,
      );

      final result = await recalculateFull(route, atB);
      final newDistance = result.route.remainingLegs
          .fold<double>(0, (sum, leg) => sum + leg.distanceMeters);

      // A ordem antiga sairia de 'b', iria até 'a' e voltaria para 'b'.
      expect(
        result.savedDistanceMeters,
        greaterThan(newDistance * 0.5),
        reason: 'evitar o retorno é a maior parte da economia',
      );
    });

    test('sem pendentes não há o que recalcular', () async {
      final route = _routeOf([
        _stop('a', 1, status: StopStatus.delivered),
        _stop('b', 5, status: StopStatus.delivered),
      ]);

      final result =
          await repository.recalculateFrom(route: route, origin: _start);

      expect(result.isLeft(), isTrue);
    });

    test('parada sem coordenada não entra no recálculo', () async {
      final route = _routeOf([_stop('a', 1), _stop('b', 5)]);

      final withoutCoordinate = ActiveRoute(
        strategy: route.strategy,
        origin: route.origin,
        legs: [
          route.legs.first,
          RouteLeg(
            from: route.legs.first.to,
            to: DeliveryStop(
              id: 'sem-coordenada',
              street: 'Rua sem coordenada',
              createdAt: DateTime(2026, 7, 1),
            ),
            distanceMeters: 1000,
            durationSeconds: 120,
          ),
        ],
        travelDurationSeconds: route.travelDurationSeconds,
        serviceDurationSeconds: route.serviceDurationSeconds,
        totalDistanceMeters: route.totalDistanceMeters,
        isEstimate: true,
        startedAt: route.startedAt,
      );

      final updated = await recalculate(withoutCoordinate, _start);

      expect(updated.orderedStops.map((s) => s.id), ['a']);
    });
  });
}
