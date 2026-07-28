import 'package:flutter_test/flutter_test.dart';
import 'package:routely/core/geo/geo_point.dart';
import 'package:routely/features/routing/data/providers/haversine_matrix_provider.dart';
import 'package:routely/features/routing/domain/entities/route_strategy.dart';
import 'package:routely/features/routing/domain/entities/travel_matrix.dart';
import 'package:routely/features/routing/domain/services/route_optimizer.dart';
import 'package:routely/features/stops/domain/entities/delivery_stop.dart';

DeliveryStop _stop(String id, double lat, double lng) => DeliveryStop(
      id: id,
      street: 'Rua $id',
      coordinate: GeoPoint(latitude: lat, longitude: lng),
      createdAt: DateTime(2026, 1, 1),
    );

Future<TravelMatrix> _matrixFor(GeoPoint origin, List<DeliveryStop> stops) async {
  const provider = HaversineMatrixProvider();
  final result = await provider.buildMatrix(
    [origin, ...stops.map((s) => s.coordinate!)],
  );
  return result.getOrElse(() => throw StateError('matriz não construída'));
}

double _totalCost(List<int> order, TravelMatrix matrix) {
  var total = 0.0;
  for (var i = 1; i < order.length; i++) {
    total += matrix.durationBetween(order[i - 1], order[i]);
  }
  return total;
}

void main() {
  const optimizer = RouteOptimizer();
  const serviceTime = Duration(minutes: 3);

  // Origem no centro de Campinas.
  const origin = GeoPoint(latitude: -22.9099, longitude: -47.0626);

  group('RouteOptimizer', () {
    test('visita todas as paradas exatamente uma vez', () async {
      final stops = [
        _stop('a', -22.9200, -47.0700),
        _stop('b', -22.9000, -47.0500),
        _stop('c', -22.9300, -47.0800),
        _stop('d', -22.8900, -47.0400),
      ];
      final matrix = await _matrixFor(origin, stops);

      final option = optimizer.optimize(
        strategy: RouteStrategy.fastest,
        stops: stops,
        matrix: matrix,
        serviceTimePerStop: serviceTime,
      );

      final visitedIds = option.orderedStops.map((s) => s.id).toList();
      expect(visitedIds, hasLength(stops.length));
      expect(visitedIds.toSet(), stops.map((s) => s.id).toSet());
    });

    test('soma o tempo de parada ao total', () async {
      final stops = [
        _stop('a', -22.9200, -47.0700),
        _stop('b', -22.9000, -47.0500),
      ];
      final matrix = await _matrixFor(origin, stops);

      final option = optimizer.optimize(
        strategy: RouteStrategy.fastest,
        stops: stops,
        matrix: matrix,
        serviceTimePerStop: serviceTime,
      );

      expect(option.serviceDurationSeconds, 2 * 180);
      expect(
        option.totalDurationSeconds,
        option.travelDurationSeconds + option.serviceDurationSeconds,
      );
    });

    test('nearestFirst começa pela parada mais próxima da origem', () async {
      final farthest = _stop('longe', -22.9600, -47.1200);
      final nearest = _stop('perto', -22.9110, -47.0640);
      final middle = _stop('meio', -22.9300, -47.0900);

      // Ordem de entrada propositalmente diferente da esperada.
      final stops = [farthest, middle, nearest];
      final matrix = await _matrixFor(origin, stops);

      final option = optimizer.optimize(
        strategy: RouteStrategy.nearestFirst,
        stops: stops,
        matrix: matrix,
        serviceTimePerStop: serviceTime,
      );

      expect(option.orderedStops.first.id, 'perto');
    });

    test('2-opt nunca piora a solução do vizinho-mais-próximo', () async {
      // Layout em zigue-zague: o guloso cai numa ordem ruim aqui, que é
      // exatamente o caso que o 2-opt existe para consertar.
      final stops = [
        _stop('a', -22.9000, -47.0600),
        _stop('b', -22.9500, -47.0620),
        _stop('c', -22.9050, -47.0900),
        _stop('d', -22.9450, -47.0910),
        _stop('e', -22.9100, -47.1200),
        _stop('f', -22.9400, -47.1210),
      ];
      final matrix = await _matrixFor(origin, stops);

      final refined = optimizer.optimize(
        strategy: RouteStrategy.fastest,
        stops: stops,
        matrix: matrix,
        serviceTimePerStop: serviceTime,
      );
      final greedy = optimizer.optimize(
        strategy: RouteStrategy.nearestFirst,
        stops: stops,
        matrix: matrix,
        serviceTimePerStop: serviceTime,
      );

      expect(
        refined.travelDurationSeconds,
        lessThanOrEqualTo(greedy.travelDurationSeconds),
      );
    });

    test('parada única gera rota com um trecho só', () async {
      final stops = [_stop('unica', -22.9200, -47.0700)];
      final matrix = await _matrixFor(origin, stops);

      final option = optimizer.optimize(
        strategy: RouteStrategy.fastest,
        stops: stops,
        matrix: matrix,
        serviceTimePerStop: serviceTime,
      );

      expect(option.legs, hasLength(1));
      expect(option.legs.first.from, isNull);
      expect(option.legs.first.to.id, 'unica');
    });

    test('os totais batem com a soma dos trechos', () async {
      final stops = [
        _stop('a', -22.9200, -47.0700),
        _stop('b', -22.9000, -47.0500),
        _stop('c', -22.9300, -47.0800),
      ];
      final matrix = await _matrixFor(origin, stops);

      final option = optimizer.optimize(
        strategy: RouteStrategy.shortest,
        stops: stops,
        matrix: matrix,
        serviceTimePerStop: serviceTime,
      );

      final legDistance =
          option.legs.fold<double>(0, (sum, l) => sum + l.distanceMeters);
      final legDuration =
          option.legs.fold<double>(0, (sum, l) => sum + l.durationSeconds);

      expect(option.totalDistanceMeters, closeTo(legDistance, 0.001));
      expect(option.travelDurationSeconds, closeTo(legDuration, 0.001));
    });
  });

  group('HaversineMatrixProvider', () {
    test('matriz é simétrica e tem diagonal zero', () async {
      final stops = [
        _stop('a', -22.9200, -47.0700),
        _stop('b', -22.9000, -47.0500),
      ];
      final matrix = await _matrixFor(origin, stops);

      for (var i = 0; i < matrix.size; i++) {
        expect(matrix.durationBetween(i, i), 0);
        for (var j = 0; j < matrix.size; j++) {
          expect(
            matrix.durationBetween(i, j),
            closeTo(matrix.durationBetween(j, i), 0.001),
          );
        }
      }
    });

    test('aplica o fator de sinuosidade sobre a linha reta', () async {
      const provider = HaversineMatrixProvider(sinuosityFactor: 1.35);
      const a = GeoPoint(latitude: -22.9099, longitude: -47.0626);
      const b = GeoPoint(latitude: -22.9199, longitude: -47.0626);

      final result = await provider.buildMatrix([a, b]);
      final matrix = result.getOrElse(() => throw StateError('falhou'));

      expect(
        matrix.distanceBetween(0, 1),
        closeTo(a.haversineDistanceTo(b) * 1.35, 0.001),
      );
    });

    test('menos de dois pontos não gera rota', () async {
      const provider = HaversineMatrixProvider();
      final result = await provider.buildMatrix([origin]);
      expect(result.isLeft(), isTrue);
    });
  });

  group('cenário realista', () {
    test('roteiro de 12 entregas é resolvido sem explodir', () async {
      final stops = List.generate(
        12,
        (i) => _stop(
          'p$i',
          -22.90 - (i % 4) * 0.012,
          -47.05 - (i ~/ 4) * 0.015,
        ),
      );
      final matrix = await _matrixFor(origin, stops);

      final option = optimizer.optimize(
        strategy: RouteStrategy.fastest,
        stops: stops,
        matrix: matrix,
        serviceTimePerStop: serviceTime,
      );

      expect(option.orderedStops, hasLength(12));

      // Sanidade: a rota refinada tem que ser melhor que a ordem de cadastro.
      final naiveOrder = List.generate(13, (i) => i);
      expect(
        option.travelDurationSeconds,
        lessThanOrEqualTo(_totalCost(naiveOrder, matrix)),
      );
    });
  });
}
