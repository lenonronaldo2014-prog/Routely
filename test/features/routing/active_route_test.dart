import 'package:flutter_test/flutter_test.dart';
import 'package:routely/core/geo/geo_point.dart';
import 'package:routely/features/routing/domain/entities/active_route.dart';
import 'package:routely/features/routing/domain/entities/route_option.dart';
import 'package:routely/features/routing/domain/entities/route_strategy.dart';
import 'package:routely/features/stops/domain/entities/delivery_stop.dart';

DeliveryStop _stop(
  String id, {
  StopStatus status = StopStatus.pending,
}) =>
    DeliveryStop(
      id: id,
      street: 'Rua $id',
      number: '10',
      coordinate: const GeoPoint(latitude: -23.55, longitude: -46.63),
      status: status,
      createdAt: DateTime(2026, 1, 1),
    );

ActiveRoute _route(List<DeliveryStop> stops) {
  final legs = <RouteLeg>[];
  for (var i = 0; i < stops.length; i++) {
    legs.add(RouteLeg(
      from: i == 0 ? null : stops[i - 1],
      to: stops[i],
      distanceMeters: 2000,
      durationSeconds: 300,
    ));
  }

  return ActiveRoute(
    strategy: RouteStrategy.fastest,
    origin: const GeoPoint(latitude: -23.5505, longitude: -46.6333),
    legs: legs,
    travelDurationSeconds: 300.0 * stops.length,
    serviceDurationSeconds: 180.0 * stops.length,
    totalDistanceMeters: 2000.0 * stops.length,
    isEstimate: true,
    startedAt: DateTime(2026, 7, 26, 8),
  );
}

void main() {
  group('ActiveRoute', () {
    test('conta entregues e pendentes', () {
      final route = _route([
        _stop('a', status: StopStatus.delivered),
        _stop('b'),
        _stop('c'),
      ]);

      expect(route.totalStops, 3);
      expect(route.deliveredCount, 1);
      expect(route.remainingLegs, hasLength(2));
      expect(route.progress, closeTo(1 / 3, 0.001));
      expect(route.isComplete, isFalse);
    });

    test('a próxima parada é a primeira pendente na ordem', () {
      final route = _route([
        _stop('a', status: StopStatus.delivered),
        _stop('b', status: StopStatus.delivered),
        _stop('c'),
        _stop('d'),
      ]);

      expect(route.nextStop?.id, 'c');
    });

    test('sem pendentes a rota está completa', () {
      final route = _route([
        _stop('a', status: StopStatus.delivered),
        _stop('b', status: StopStatus.failed),
      ]);

      expect(route.isComplete, isTrue);
      expect(route.nextStop, isNull);
      expect(route.progress, 1.0);
    });

    // O que importa no meio do dia é o que falta, não o roteiro inteiro.
    test('tempo e distância restantes ignoram o que já foi entregue', () {
      final route = _route([
        _stop('a', status: StopStatus.delivered),
        _stop('b'),
        _stop('c'),
      ]);

      expect(route.remainingDistanceMeters, 4000);
      expect(route.remainingTravelSeconds, 600);
      // 540s de parada no total (3 × 180), 2 paradas restantes = 360s.
      expect(route.remainingServiceSeconds, closeTo(360, 0.001));
      expect(route.remainingTotalSeconds, closeTo(960, 0.001));
      expect(route.formattedRemainingDuration, '16min');
      expect(route.formattedRemainingDistance, '4,0 km');
    });

    group('withRefreshedStops', () {
      test('reflete o status novo das paradas', () {
        final route = _route([_stop('a'), _stop('b')]);
        expect(route.deliveredCount, 0);

        final refreshed = route.withRefreshedStops([
          _stop('a', status: StopStatus.delivered),
          _stop('b'),
        ]);

        expect(refreshed.deliveredCount, 1);
        expect(refreshed.nextStop?.id, 'b');
      });

      test('descarta trechos cuja parada foi apagada', () {
        final route = _route([_stop('a'), _stop('b'), _stop('c')]);

        final refreshed = route.withRefreshedStops([_stop('a'), _stop('c')]);

        expect(refreshed.totalStops, 2);
        expect(
          refreshed.orderedStops.map((s) => s.id),
          ['a', 'c'],
          reason: 'a ordem original tem que ser preservada',
        );
      });

      test('apagar tudo deixa a rota vazia', () {
        final route = _route([_stop('a'), _stop('b')]);

        final refreshed = route.withRefreshedStops([]);

        expect(refreshed.legs, isEmpty);
        expect(refreshed.isComplete, isTrue);
      });
    });

    test('fromOption preserva a ordem e os totais', () {
      final stops = [_stop('a'), _stop('b')];
      final option = RouteOption(
        strategy: RouteStrategy.shortest,
        legs: [
          RouteLeg(to: stops[0], distanceMeters: 1500, durationSeconds: 200),
          RouteLeg(
            from: stops[0],
            to: stops[1],
            distanceMeters: 2500,
            durationSeconds: 400,
          ),
        ],
        travelDurationSeconds: 600,
        serviceDurationSeconds: 360,
        totalDistanceMeters: 4000,
        isEstimate: true,
      );

      final route = ActiveRoute.fromOption(
        option: option,
        origin: const GeoPoint(latitude: -23.55, longitude: -46.63),
        startedAt: DateTime(2026, 7, 26, 9),
      );

      expect(route.strategy, RouteStrategy.shortest);
      expect(route.orderedStops.map((s) => s.id), ['a', 'b']);
      expect(route.totalDistanceMeters, 4000);
      expect(route.serviceDurationSeconds, 360);
      expect(route.isEstimate, isTrue);
    });
  });
}
