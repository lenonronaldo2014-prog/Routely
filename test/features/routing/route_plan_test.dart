import 'package:flutter_test/flutter_test.dart';
import 'package:routely/core/config/plan_limits.dart';
import 'package:routely/core/geo/geo_point.dart';
import 'package:routely/core/settings/app_settings.dart';
import 'package:routely/features/routing/data/providers/haversine_matrix_provider.dart';
import 'package:routely/features/routing/data/repositories/routing_repository_impl.dart';
import 'package:routely/features/routing/domain/entities/route_plan.dart';
import 'package:routely/features/routing/domain/services/route_optimizer.dart';
import 'package:routely/features/stops/domain/entities/delivery_stop.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'route_local_data_source_test_stub.dart';

/// Origem: centro de São Paulo.
const _origin = GeoPoint(latitude: -23.5505, longitude: -46.6333);

/// Cria uma parada a [km] quilômetros ao norte da origem — assim a ordem por
/// proximidade fica previsível no teste.
DeliveryStop _stopAt(String id, double km) => DeliveryStop(
      id: id,
      street: 'Rua $id',
      // ~0.009 grau de latitude por km.
      coordinate: GeoPoint(
        latitude: _origin.latitude - km * 0.009,
        longitude: _origin.longitude,
      ),
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late RoutingRepositoryImpl repository;
  late AppSettings settings;

  Future<void> buildRepository({PlanTier tier = PlanTier.free}) async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
    await settings.setPlanTier(tier);

    repository = RoutingRepositoryImpl(
      matrixProvider: const HaversineMatrixProvider(),
      optimizer: const RouteOptimizer(),
      settings: settings,
      localDataSource: NoopRouteLocalDataSource(),
    );
  }

  Future<RoutePlan> calculate(List<DeliveryStop> stops) async {
    final result =
        await repository.calculateOptions(origin: _origin, stops: stops);
    return result.getOrElse(() => throw StateError('cálculo falhou'));
  }

  group('limite do plano gratuito', () {
    setUp(() => buildRepository());

    test('o teto é 8 entregas por rota', () {
      expect(PlanTier.free.maxStopsPerRoute, 8);
    });

    test('abaixo do limite nada é adiado', () async {
      final stops = List.generate(5, (i) => _stopAt('p$i', (i + 1).toDouble()));

      final plan = await calculate(stops);

      expect(plan.batchStops, hasLength(5));
      expect(plan.hasDeferred, isFalse);
      expect(plan.totalBatches, 1);
    });

    test('exatamente 8 ainda cabe num grupo só', () async {
      final stops = List.generate(8, (i) => _stopAt('p$i', (i + 1).toDouble()));

      final plan = await calculate(stops);

      expect(plan.batchStops, hasLength(8));
      expect(plan.hasDeferred, isFalse);
      expect(plan.totalBatches, 1);
    });

    test('acima de 8 as demais viram próximo grupo', () async {
      final stops = List.generate(12, (i) => _stopAt('p$i', (i + 1).toDouble()));

      final plan = await calculate(stops);

      expect(plan.batchStops, hasLength(8));
      expect(plan.deferredCount, 4);
      expect(plan.totalStops, 12);
      expect(plan.totalBatches, 2);
    });

    test('20 entregas viram 3 grupos', () async {
      final stops = List.generate(20, (i) => _stopAt('p$i', (i + 1).toDouble()));

      final plan = await calculate(stops);

      expect(plan.totalBatches, 3);
    });

    // O ponto central: o primeiro grupo é o mais perto de onde o cara está.
    test('entram as 8 mais próximas da origem', () async {
      final stops = [
        _stopAt('longe1', 40),
        _stopAt('perto1', 1),
        _stopAt('longe2', 35),
        _stopAt('perto2', 2),
        _stopAt('perto3', 3),
        _stopAt('perto4', 4),
        _stopAt('perto5', 5),
        _stopAt('perto6', 6),
        _stopAt('perto7', 7),
        _stopAt('perto8', 8),
      ];

      final plan = await calculate(stops);

      final batchIds = plan.batchStops.map((s) => s.id).toSet();
      expect(batchIds, hasLength(8));
      expect(batchIds.contains('longe1'), isFalse);
      expect(batchIds.contains('longe2'), isFalse);

      expect(
        plan.deferredStops.map((s) => s.id).toSet(),
        {'longe1', 'longe2'},
      );
    });

    test('as adiadas voltam ordenadas da mais próxima para a mais longe',
        () async {
      final stops = [
        for (var i = 1; i <= 8; i++) _stopAt('perto$i', i.toDouble()),
        _stopAt('media', 20),
        _stopAt('longe', 50),
        _stopAt('longissima', 90),
      ];

      final plan = await calculate(stops);

      expect(
        plan.deferredStops.map((s) => s.id),
        ['media', 'longe', 'longissima'],
      );
    });

    test('a rota calculada cobre só o grupo atual', () async {
      final stops = List.generate(15, (i) => _stopAt('p$i', (i + 1).toDouble()));

      final plan = await calculate(stops);

      for (final option in plan.options) {
        expect(option.stopCount, 8);
      }
    });

    test('paradas sem coordenada não ocupam vaga no grupo', () async {
      final stops = <DeliveryStop>[
        for (var i = 1; i <= 8; i++) _stopAt('ok$i', i.toDouble()),
        DeliveryStop(
          id: 'sem-coordenada',
          street: 'Rua sem coordenada',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final plan = await calculate(stops);

      expect(plan.batchStops, hasLength(8));
      expect(
        plan.hasDeferred,
        isFalse,
        reason: 'a parada sem coordenada não é roteável, então não conta',
      );
    });
  });

  group('plano pro', () {
    setUp(() => buildRepository(tier: PlanTier.pro));

    test('não fatia um roteiro de 30 entregas', () async {
      final stops = List.generate(30, (i) => _stopAt('p$i', (i + 1).toDouble()));

      final plan = await calculate(stops);

      expect(plan.batchStops, hasLength(30));
      expect(plan.hasDeferred, isFalse);
      expect(plan.totalBatches, 1);
      expect(plan.tier, PlanTier.pro);
    });
  });
}
