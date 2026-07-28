import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../domain/entities/delivery_record.dart';
import '../../domain/entities/delivery_stop.dart';

abstract class HistoryLocalDataSource {
  /// Move as concluídas de `stops` para o histórico. Devolve quantas foram.
  Future<int> archiveCompleted();

  Future<List<DeliveryRecord>> getHistory({int limit = 500});

  Future<void> clearHistory();
}

class HistoryLocalDataSourceImpl implements HistoryLocalDataSource {
  final AppDatabase appDatabase;

  HistoryLocalDataSourceImpl({required this.appDatabase});

  @override
  Future<int> archiveCompleted() async {
    try {
      final db = await appDatabase.database;
      var archived = 0;

      // Transação: mover é copiar-e-apagar. Se falhasse no meio, a entrega
      // sumiria dos dois lados.
      await db.transaction((txn) async {
        // O LEFT JOIN traz a distância do trecho quando a parada fazia parte
        // de uma rota — é o que permite somar os quilômetros do dia. Entrega
        // concluída fora de rota simplesmente vem sem distância.
        final completed = await txn.rawQuery('''
          SELECT s.*, l.distance_meters
          FROM stops s
          LEFT JOIN active_route_legs l ON l.stop_id = s.id
          WHERE s.status != 'pending'
        ''');

        for (final row in completed) {
          final id = row['id'] as String;

          await txn.insert(
            'delivery_history',
            {
              'id': id,
              'label': row['label'],
              'street': row['street'],
              'number': row['number'],
              'complement': row['complement'],
              'neighborhood': row['neighborhood'],
              'city': row['city'],
              'state': row['state'],
              'cep': row['cep'],
              'latitude': row['latitude'],
              'longitude': row['longitude'],
              'notes': row['notes'],
              'status': row['status'],
              'created_at': row['created_at'],
              // Concluída sem carimbo de data não deveria acontecer, mas se
              // acontecer é melhor arquivar com "agora" do que perder.
              'completed_at':
                  row['completed_at'] ?? DateTime.now().millisecondsSinceEpoch,
              'distance_meters': row['distance_meters'],
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          await txn.delete('stops', where: 'id = ?', whereArgs: [id]);
          archived++;
        }
      });

      return archived;
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<List<DeliveryRecord>> getHistory({int limit = 500}) async {
    try {
      final db = await appDatabase.database;
      final rows = await db.query(
        'delivery_history',
        orderBy: 'completed_at DESC',
        limit: limit,
      );

      return rows.map(_fromMap).toList();
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> clearHistory() async {
    try {
      final db = await appDatabase.database;
      await db.delete('delivery_history');
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  DeliveryRecord _fromMap(Map<String, Object?> row) => DeliveryRecord(
        id: row['id'] as String,
        label: row['label'] as String?,
        street: row['street'] as String,
        number: row['number'] as String?,
        neighborhood: row['neighborhood'] as String?,
        city: row['city'] as String?,
        state: row['state'] as String?,
        cep: row['cep'] as String?,
        status: StopStatus.fromName(row['status'] as String),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        completedAt:
            DateTime.fromMillisecondsSinceEpoch(row['completed_at'] as int),
        distanceMeters: row['distance_meters'] as double?,
      );
}
