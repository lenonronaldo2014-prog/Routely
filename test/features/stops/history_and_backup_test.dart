import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:routely/core/database/app_database.dart';
import 'package:routely/core/geo/geo_point.dart';
import 'package:routely/features/stops/data/datasources/backup_data_source.dart';
import 'package:routely/features/stops/data/datasources/cep_directory_local_data_source.dart';
import 'package:routely/features/stops/data/datasources/history_local_data_source.dart';
import 'package:routely/features/stops/data/datasources/stops_local_data_source.dart';
import 'package:routely/features/stops/data/models/stop_model.dart';
import 'package:routely/features/stops/domain/entities/delivery_stop.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase appDatabase;
  late StopsLocalDataSourceImpl stops;
  late HistoryLocalDataSourceImpl history;
  late BackupDataSourceImpl backup;
  late CepDirectoryLocalDataSourceImpl directory;

  const dbName = 'routely_history_test.db';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    await databaseFactory
        .deleteDatabase(p.join(await getDatabasesPath(), dbName));
    appDatabase = AppDatabase(databaseName: dbName);
    stops = StopsLocalDataSourceImpl(appDatabase: appDatabase);
    history = HistoryLocalDataSourceImpl(appDatabase: appDatabase);
    backup = BackupDataSourceImpl(appDatabase: appDatabase);
    directory = CepDirectoryLocalDataSourceImpl(appDatabase: appDatabase);
  });

  tearDown(() async => appDatabase.close());

  StopModel stop(
    String id, {
    StopStatus status = StopStatus.pending,
    DateTime? completedAt,
  }) =>
      StopModel(
        id: id,
        street: 'Rua $id',
        number: '100',
        city: 'São Paulo',
        state: 'SP',
        coordinate: const GeoPoint(latitude: -23.55, longitude: -46.63),
        status: status,
        createdAt: DateTime(2026, 7, 1),
        completedAt: completedAt,
      );

  group('arquivar em vez de apagar', () {
    // O motivo da feature: antes, limpar concluídas deletava e o entregador
    // perdia o registro do próprio dia de trabalho.
    test('as concluídas vão para o histórico', () async {
      await stops.upsertStop(stop('a',
          status: StopStatus.delivered, completedAt: DateTime(2026, 7, 26, 9)));
      await stops.upsertStop(stop('b'));

      final archived = await history.archiveCompleted();

      expect(archived, 1);
      expect(await stops.getStops(), hasLength(1));

      final records = await history.getHistory();
      expect(records, hasLength(1));
      expect(records.first.id, 'a');
      expect(records.first.wasDelivered, isTrue);
    });

    test('as pendentes ficam na lista', () async {
      await stops.upsertStop(stop('a', status: StopStatus.delivered));
      await stops.upsertStop(stop('b'));
      await stops.upsertStop(stop('c'));

      await history.archiveCompleted();

      final remaining = await stops.getStops();
      expect(remaining.map((s) => s.id), unorderedEquals(['b', 'c']));
    });

    test('não entregue também é arquivado, com o status certo', () async {
      await stops.upsertStop(stop('a',
          status: StopStatus.failed, completedAt: DateTime(2026, 7, 26)));

      await history.archiveCompleted();

      final records = await history.getHistory();
      expect(records.first.wasDelivered, isFalse);
      expect(records.first.status, StopStatus.failed);
    });

    test('arquivar duas vezes não duplica', () async {
      await stops.upsertStop(stop('a', status: StopStatus.delivered));
      await history.archiveCompleted();
      await history.archiveCompleted();

      expect(await history.getHistory(), hasLength(1));
    });

    // Sem a distância não dá para dizer quanto o dia rendeu em quilômetros.
    test('traz a distância do trecho quando a parada estava em rota', () async {
      await stops.upsertStop(stop('a', status: StopStatus.delivered));

      final db = await appDatabase.database;
      await db.insert('active_route', {
        'id': 1,
        'strategy': 'fastest',
        'origin_latitude': -23.55,
        'origin_longitude': -46.63,
        'travel_seconds': 300.0,
        'service_seconds': 180.0,
        'distance_meters': 2500.0,
        'is_estimate': 1,
        'started_at': DateTime(2026, 7, 26).millisecondsSinceEpoch,
      });
      await db.insert('active_route_legs', {
        'position': 0,
        'stop_id': 'a',
        'distance_meters': 2500.0,
        'duration_seconds': 300.0,
      });

      await history.archiveCompleted();

      final records = await history.getHistory();
      expect(records.first.distanceMeters, 2500.0);
    });

    test('entrega fora de rota é arquivada sem distância', () async {
      await stops.upsertStop(stop('a', status: StopStatus.delivered));

      await history.archiveCompleted();

      expect((await history.getHistory()).first.distanceMeters, isNull);
    });
  });

  group('backup', () {
    test('exporta e importa de volta sem perder nada', () async {
      await stops.upsertStop(stop('a'));
      await stops.upsertStop(stop('b',
          status: StopStatus.delivered, completedAt: DateTime(2026, 7, 26)));
      await history.archiveCompleted();

      final content = await backup.export();

      // Simula aparelho novo: banco zerado.
      await appDatabase.close();
      await databaseFactory
          .deleteDatabase(p.join(await getDatabasesPath(), dbName));
      appDatabase = AppDatabase(databaseName: dbName);
      final freshStops = StopsLocalDataSourceImpl(appDatabase: appDatabase);
      final freshHistory = HistoryLocalDataSourceImpl(appDatabase: appDatabase);
      final freshBackup = BackupDataSourceImpl(appDatabase: appDatabase);

      final summary = await freshBackup.import(content);

      expect(summary.stops, 1);
      expect(summary.history, 1);
      expect((await freshStops.getStops()).single.id, 'a');
      expect((await freshHistory.getHistory()).single.id, 'b');
    });

    test('importar substitui o que estava no aparelho', () async {
      await stops.upsertStop(stop('antiga'));
      final content = await backup.export();

      await stops.upsertStop(stop('nova'));
      await backup.import(content);

      final remaining = await stops.getStops();
      expect(remaining.map((s) => s.id), ['antiga']);
    });

    test('arquivo de outro app é recusado', () async {
      expect(
        () => backup.import('{"format":"outra-coisa","version":1}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('arquivo corrompido é recusado', () async {
      expect(
        () => backup.import('isso não é json'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('backup de versão futura é recusado com aviso', () async {
      expect(
        () => backup.import('{"format":"routely-backup","version":99}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('a rota em andamento é limpa na importação', () async {
      await stops.upsertStop(stop('a'));
      final content = await backup.export();

      final db = await appDatabase.database;
      await db.insert('active_route', {
        'id': 1,
        'strategy': 'fastest',
        'origin_latitude': -23.55,
        'origin_longitude': -46.63,
        'travel_seconds': 300.0,
        'service_seconds': 180.0,
        'distance_meters': 2500.0,
        'is_estimate': 1,
        'started_at': DateTime(2026, 7, 26).millisecondsSinceEpoch,
      });

      await backup.import(content);

      final route = await db.query('active_route');
      expect(
        route,
        isEmpty,
        reason: 'apontaria para paradas que foram substituídas',
      );
    });
  });

  group('coordenada vinda do CEP', () {
    // É o que torna o app gratuito de operar em escala.
    test('a base guarda e devolve lat/lng', () async {
      await directory.importState(
        state: 'SP',
        lines: Stream.fromIterable([
          '01310-100;Avenida Paulista;Bela Vista;São Paulo;SP;-23.5613;-46.6560',
        ]),
      );

      final lookup = await directory.lookup('01310100');

      expect(lookup, isNotNull);
      expect(lookup!.hasCoordinate, isTrue);
      expect(lookup.coordinate!.latitude, closeTo(-23.5613, 0.00001));
      expect(lookup.coordinate!.longitude, closeTo(-46.6560, 0.00001));
    });

    test('arquivo antigo de 5 colunas continua valendo', () async {
      await directory.importState(
        state: 'SP',
        lines: Stream.fromIterable([
          '01001-000;Praça da Sé;Sé;São Paulo;SP',
        ]),
      );

      final lookup = await directory.lookup('01001000');

      expect(lookup, isNotNull);
      expect(lookup!.city, 'São Paulo');
      expect(lookup.hasCoordinate, isFalse);
    });

    test('aceita vírgula como separador decimal', () async {
      await directory.importState(
        state: 'SP',
        lines: Stream.fromIterable([
          '01310-100;Avenida Paulista;Bela Vista;São Paulo;SP;-23,5613;-46,6560',
        ]),
      );

      expect((await directory.lookup('01310100'))!.hasCoordinate, isTrue);
    });

    // Coordenada fora de faixa manda o entregador para o oceano.
    test('descarta coordenada fora de faixa', () async {
      await directory.importState(
        state: 'SP',
        lines: Stream.fromIterable([
          '01310-100;Avenida Paulista;Bela Vista;São Paulo;SP;999;-46.6560',
        ]),
      );

      expect((await directory.lookup('01310100'))!.hasCoordinate, isFalse);
    });

    test('descarta coordenada zerada', () async {
      await directory.importState(
        state: 'SP',
        lines: Stream.fromIterable([
          '01310-100;Avenida Paulista;Bela Vista;São Paulo;SP;0;0',
        ]),
      );

      expect((await directory.lookup('01310100'))!.hasCoordinate, isFalse);
    });
  });
}
