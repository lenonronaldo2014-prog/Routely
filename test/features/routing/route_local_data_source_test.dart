import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:routely/core/database/app_database.dart';
import 'package:routely/core/geo/geo_point.dart';
import 'package:routely/features/routing/data/datasources/route_local_data_source.dart';
import 'package:routely/features/routing/domain/entities/active_route.dart';
import 'package:routely/features/routing/domain/entities/route_option.dart';
import 'package:routely/features/routing/domain/entities/route_strategy.dart';
import 'package:routely/features/stops/data/datasources/stops_local_data_source.dart';
import 'package:routely/features/stops/data/models/stop_model.dart';
import 'package:routely/features/stops/domain/entities/delivery_stop.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite de verdade, em memória. É o único jeito de provar que a rota
/// realmente sobrevive — mock de banco não pega erro de schema, de transação
/// nem de chave estrangeira.
void main() {
  late AppDatabase appDatabase;
  late RouteLocalDataSourceImpl routeSource;
  late StopsLocalDataSourceImpl stopsSource;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // Nome próprio: o `flutter test` roda arquivos em paralelo, e compartilhar o
  // banco com outro arquivo de teste dava falha intermitente.
  const dbName = 'routely_route_test.db';

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    // Apaga o arquivo antes de cada teste. Sem isso os testes herdam as
    // paradas uns dos outros e passam a mentir.
    await databaseFactory
        .deleteDatabase(p.join(await getDatabasesPath(), dbName));
    appDatabase = AppDatabase(databaseName: dbName);
    routeSource = RouteLocalDataSourceImpl(appDatabase: appDatabase);
    stopsSource = StopsLocalDataSourceImpl(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  StopModel stop(String id, {StopStatus status = StopStatus.pending}) =>
      StopModel(
        id: id,
        street: 'Rua $id',
        number: '100',
        city: 'São Paulo',
        state: 'SP',
        coordinate: GeoPoint(
          latitude: -23.55 - id.codeUnitAt(0) / 10000,
          longitude: -46.63,
        ),
        status: status,
        createdAt: DateTime(2026, 1, 1),
      );

  Future<ActiveRoute> seedRoute(List<StopModel> stops) async {
    for (final s in stops) {
      await stopsSource.upsertStop(s);
    }

    final legs = <RouteLeg>[];
    for (var i = 0; i < stops.length; i++) {
      legs.add(RouteLeg(
        from: i == 0 ? null : stops[i - 1],
        to: stops[i],
        distanceMeters: 1000.0 * (i + 1),
        durationSeconds: 120.0 * (i + 1),
      ));
    }

    final route = ActiveRoute(
      strategy: RouteStrategy.shortest,
      origin: const GeoPoint(latitude: -23.5505, longitude: -46.6333),
      legs: legs,
      travelDurationSeconds: 720,
      serviceDurationSeconds: 540,
      totalDistanceMeters: 6000,
      isEstimate: true,
      startedAt: DateTime(2026, 7, 26, 8, 30),
    );

    await routeSource.saveActiveRoute(route);
    return route;
  }

  group('RouteLocalDataSource', () {
    test('sem rota gravada retorna null', () async {
      expect(await routeSource.getActiveRoute(), isNull);
    });

    test('a rota sobrevive ao round-trip no banco', () async {
      final saved = await seedRoute([stop('a'), stop('b'), stop('c')]);

      final loaded = await routeSource.getActiveRoute();

      expect(loaded, isNotNull);
      expect(loaded!.strategy, RouteStrategy.shortest);
      expect(loaded.origin.latitude, closeTo(saved.origin.latitude, 0.000001));
      expect(loaded.origin.longitude, closeTo(saved.origin.longitude, 0.000001));
      expect(loaded.travelDurationSeconds, 720);
      expect(loaded.serviceDurationSeconds, 540);
      expect(loaded.totalDistanceMeters, 6000);
      expect(loaded.isEstimate, isTrue);
      expect(loaded.startedAt, saved.startedAt);
    });

    test('a ordem das paradas é preservada', () async {
      await seedRoute([stop('c'), stop('a'), stop('b')]);

      final loaded = await routeSource.getActiveRoute();

      expect(loaded!.orderedStops.map((s) => s.id), ['c', 'a', 'b']);
    });

    test('os trechos mantêm distância e tempo', () async {
      await seedRoute([stop('a'), stop('b')]);

      final loaded = await routeSource.getActiveRoute();

      expect(loaded!.legs[0].distanceMeters, 1000);
      expect(loaded.legs[0].durationSeconds, 120);
      expect(loaded.legs[1].distanceMeters, 2000);
      expect(loaded.legs[1].durationSeconds, 240);
    });

    test('o primeiro trecho parte da origem, não de uma parada', () async {
      await seedRoute([stop('a'), stop('b')]);

      final loaded = await routeSource.getActiveRoute();

      expect(loaded!.legs.first.from, isNull);
      expect(loaded.legs[1].from?.id, 'a');
    });

    // O cenário que motiva a feature: app morto no meio do roteiro.
    test('o progresso marcado antes do fechamento é recuperado', () async {
      await seedRoute([stop('a'), stop('b'), stop('c')]);

      // Entregou a primeira e o app morreu.
      await stopsSource.upsertStop(stop('a', status: StopStatus.delivered));
      await appDatabase.close();

      // Abriu de novo.
      final reopened = AppDatabase(databaseName: dbName);
      final source = RouteLocalDataSourceImpl(appDatabase: reopened);
      final loaded = await source.getActiveRoute();
      await reopened.close();

      expect(loaded, isNotNull);
      expect(loaded!.deliveredCount, 1);
      expect(loaded.nextStop?.id, 'b');
      expect(loaded.remainingLegs, hasLength(2));
    });

    test('apagar uma parada tira o trecho da rota', () async {
      await seedRoute([stop('a'), stop('b'), stop('c')]);

      await stopsSource.deleteStop('b');

      final loaded = await routeSource.getActiveRoute();

      expect(loaded!.orderedStops.map((s) => s.id), ['a', 'c']);
    });

    test('apagar todas as paradas limpa a rota', () async {
      await seedRoute([stop('a'), stop('b')]);

      await stopsSource.deleteStop('a');
      await stopsSource.deleteStop('b');

      expect(await routeSource.getActiveRoute(), isNull);
    });

    test('salvar de novo substitui a rota anterior', () async {
      await seedRoute([stop('a'), stop('b')]);
      await seedRoute([stop('x'), stop('y'), stop('z')]);

      final loaded = await routeSource.getActiveRoute();

      expect(loaded!.orderedStops.map((s) => s.id), ['x', 'y', 'z']);
    });

    test('encerrar remove a rota mas mantém as paradas', () async {
      await seedRoute([stop('a'), stop('b')]);

      await routeSource.clearActiveRoute();

      expect(await routeSource.getActiveRoute(), isNull);
      expect(await stopsSource.getStops(), hasLength(2));
    });
  });
}
