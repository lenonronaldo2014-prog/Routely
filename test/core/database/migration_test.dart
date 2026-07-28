import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:routely/core/database/app_database.dart';
import 'package:routely/features/routing/data/datasources/route_local_data_source.dart';
import 'package:routely/features/stops/data/datasources/stops_local_data_source.dart';
import 'package:routely/features/stops/domain/entities/delivery_stop.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Migrações não podem perder dado.
///
/// Este arquivo existe porque, num teste manual no emulador, as entregas
/// sumiram do banco depois de uma sequência de atualizações do app. Não
/// consegui reproduzir a causa, mas "a rota não pode se perder" é requisito —
/// então o caminho de atualização passa a ser verificado a cada build em vez
/// de depender de observação pontual.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const dbName = 'routely_migration_test.db';

  Future<String> dbPath() async =>
      p.join(await getDatabasesPath(), dbName);

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.deleteDatabase(await dbPath());
  });

  /// Recria o schema como era na v1 — antes das rotas e do diretório de CEP.
  Future<void> seedV1Database() async {
    final db = await databaseFactory.openDatabase(
      await dbPath(),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE stops (
              id             TEXT    PRIMARY KEY,
              label          TEXT,
              street         TEXT    NOT NULL,
              number         TEXT,
              complement     TEXT,
              neighborhood   TEXT,
              city           TEXT,
              state          TEXT,
              cep            TEXT,
              latitude       REAL,
              longitude      REAL,
              notes          TEXT,
              status         TEXT    NOT NULL DEFAULT 'pending',
              created_at     INTEGER NOT NULL,
              completed_at   INTEGER
            )
          ''');
          await db.execute('CREATE INDEX idx_stops_status ON stops(status)');
          await db.execute('''
            CREATE TABLE cep_cache (
              cep            TEXT    PRIMARY KEY,
              street         TEXT,
              neighborhood   TEXT,
              city           TEXT,
              state          TEXT,
              cached_at      INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE geocode_cache (
              address_key    TEXT    PRIMARY KEY,
              latitude       REAL    NOT NULL,
              longitude      REAL    NOT NULL,
              cached_at      INTEGER NOT NULL
            )
          ''');
        },
      ),
    );

    for (var i = 1; i <= 3; i++) {
      await db.insert('stops', {
        'id': 'stop$i',
        'street': 'Rua $i',
        'number': '10$i',
        'city': 'São Paulo',
        'state': 'SP',
        'latitude': -23.55 - i * 0.01,
        'longitude': -46.63,
        'status': i == 1 ? 'delivered' : 'pending',
        'created_at': DateTime(2026, 7, 1).millisecondsSinceEpoch,
      });
    }

    await db.insert('cep_cache', {
      'cep': '01001000',
      'street': 'Praça da Sé',
      'neighborhood': 'Sé',
      'city': 'São Paulo',
      'state': 'SP',
      'cached_at': DateTime(2026, 7, 1).millisecondsSinceEpoch,
    });

    await db.close();
  }

  group('migração v1 → atual', () {
    test('não apaga as entregas já cadastradas', () async {
      await seedV1Database();

      final appDatabase = AppDatabase(databaseName: dbName);
      final stops =
          await StopsLocalDataSourceImpl(appDatabase: appDatabase).getStops();
      await appDatabase.close();

      expect(stops, hasLength(3));
      expect(stops.map((s) => s.id), containsAll(['stop1', 'stop2', 'stop3']));
    });

    test('preserva status, coordenada e endereço', () async {
      await seedV1Database();

      final appDatabase = AppDatabase(databaseName: dbName);
      final stops =
          await StopsLocalDataSourceImpl(appDatabase: appDatabase).getStops();
      await appDatabase.close();

      final delivered = stops.firstWhere((s) => s.id == 'stop1');
      expect(delivered.status, StopStatus.delivered);
      expect(delivered.street, 'Rua 1');
      expect(delivered.number, '101');
      expect(delivered.isRoutable, isTrue);
    });

    test('preserva o cache de CEP', () async {
      await seedV1Database();

      final appDatabase = AppDatabase(databaseName: dbName);
      final db = await appDatabase.database;
      final rows = await db.query('cep_cache');
      await appDatabase.close();

      expect(rows, hasLength(1));
      expect(rows.first['street'], 'Praça da Sé');
    });

    test('cria as tabelas novas e chega na versão atual', () async {
      await seedV1Database();

      final appDatabase = AppDatabase(databaseName: dbName);
      final db = await appDatabase.database;

      expect(await db.getVersion(), 4);

      // As tabelas novas precisam existir e estar utilizáveis.
      for (final table in [
        'active_route',
        'active_route_legs',
        'cep_directory',
        'cep_directory_packs',
        'delivery_history',
      ]) {
        final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
        expect(rows.first['n'], 0, reason: '$table deveria existir e estar vazia');
      }

      await appDatabase.close();
    });

    test('a base de CEP ganha as colunas de coordenada', () async {
      await seedV1Database();

      final appDatabase = AppDatabase(databaseName: dbName);
      final db = await appDatabase.database;

      // Se as colunas não existissem, o INSERT abaixo estouraria.
      await db.insert('cep_directory', {
        'cep': '01310100',
        'street': 'Avenida Paulista',
        'neighborhood': 'Bela Vista',
        'city': 'São Paulo',
        'state': 'SP',
        'latitude': -23.5613,
        'longitude': -46.6560,
      });

      final rows = await db.query('cep_directory');
      await appDatabase.close();

      expect(rows.first['latitude'], closeTo(-23.5613, 0.00001));
      expect(rows.first['longitude'], closeTo(-46.6560, 0.00001));
    });
  });

  // Caminho que os usuários da versão anterior vão percorrer de verdade: eles
  // já têm o banco na v3 instalado, com entregas dentro.
  group('migração v3 → v4', () {
    Future<void> seedV3Database() async {
      // Chega na v3 migrando a partir da v1, que é como o banco real chegou lá.
      await seedV1Database();
      final bootstrap = AppDatabase(databaseName: dbName);
      final db = await bootstrap.database;
      await db.setVersion(3);
      // Desfaz o que a v4 criou, para simular um banco parado na v3.
      await db.execute('DROP TABLE IF EXISTS delivery_history');
      await db.execute('DROP TABLE IF EXISTS cep_directory');
      await db.execute('''
        CREATE TABLE cep_directory (
          cep            TEXT    PRIMARY KEY,
          street         TEXT,
          neighborhood   TEXT,
          city           TEXT    NOT NULL,
          state          TEXT    NOT NULL
        )
      ''');
      await db.insert('cep_directory', {
        'cep': '01001000',
        'street': 'Praça da Sé',
        'neighborhood': 'Sé',
        'city': 'São Paulo',
        'state': 'SP',
      });
      await bootstrap.close();
    }

    test('não perde entregas nem a base de CEP já instalada', () async {
      await seedV3Database();

      final appDatabase = AppDatabase(databaseName: dbName);
      final stops =
          await StopsLocalDataSourceImpl(appDatabase: appDatabase).getStops();
      final db = await appDatabase.database;
      final ceps = await db.query('cep_directory');
      final version = await db.getVersion();
      await appDatabase.close();

      expect(version, 4);
      expect(stops, hasLength(3));
      expect(ceps, hasLength(1));
      expect(
        ceps.first['latitude'],
        isNull,
        reason: 'base antiga não tinha coordenada — a coluna entra vazia',
      );
    });
  });

  group('reabrir o banco já migrado', () {
    test('abrir várias vezes não perde nada', () async {
      await seedV1Database();

      // Primeira abertura: migra.
      var appDatabase = AppDatabase(databaseName: dbName);
      final stopsSource = StopsLocalDataSourceImpl(appDatabase: appDatabase);
      final routeSource = RouteLocalDataSourceImpl(appDatabase: appDatabase);
      await appDatabase.close();

      // Simula abrir o app mais três vezes, como acontece no dia a dia.
      for (var i = 0; i < 3; i++) {
        appDatabase = AppDatabase(databaseName: dbName);
        final stops =
            await StopsLocalDataSourceImpl(appDatabase: appDatabase).getStops();
        expect(stops, hasLength(3), reason: 'abertura ${i + 2} perdeu dado');
        await appDatabase.close();
      }

      expect(stopsSource, isNotNull);
      expect(routeSource, isNotNull);
    });

    test('a rota gravada sobrevive a reaberturas seguidas', () async {
      await seedV1Database();

      final first = AppDatabase(databaseName: dbName);
      final stops = await StopsLocalDataSourceImpl(appDatabase: first).getStops();
      await first.close();

      expect(stops, isNotEmpty);

      // Grava uma rota e fecha.
      final second = AppDatabase(databaseName: dbName);
      final db = await second.database;
      await db.insert('active_route', {
        'id': 1,
        'strategy': 'fastest',
        'origin_latitude': -23.55,
        'origin_longitude': -46.63,
        'travel_seconds': 600.0,
        'service_seconds': 360.0,
        'distance_meters': 4000.0,
        'is_estimate': 1,
        'started_at': DateTime(2026, 7, 26).millisecondsSinceEpoch,
      });
      await db.insert('active_route_legs', {
        'position': 0,
        'stop_id': 'stop2',
        'distance_meters': 2000.0,
        'duration_seconds': 300.0,
      });
      await second.close();

      // Reabre e confere.
      final third = AppDatabase(databaseName: dbName);
      final route =
          await RouteLocalDataSourceImpl(appDatabase: third).getActiveRoute();
      await third.close();

      expect(route, isNotNull);
      expect(route!.orderedStops.single.id, 'stop2');
    });
  });
}
