import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../models/stop_model.dart';

abstract class StopsLocalDataSource {
  Future<List<StopModel>> getStops();
  Future<void> upsertStop(StopModel stop);
  Future<void> deleteStop(String id);
  Future<int> deleteCompleted();
}

class StopsLocalDataSourceImpl implements StopsLocalDataSource {
  final AppDatabase appDatabase;

  StopsLocalDataSourceImpl({required this.appDatabase});

  @override
  Future<List<StopModel>> getStops() async {
    try {
      final db = await appDatabase.database;
      // Pendentes primeiro; dentro de cada grupo, ordem de cadastro.
      final rows = await db.query(
        'stops',
        orderBy: "CASE status WHEN 'pending' THEN 0 ELSE 1 END, created_at ASC",
      );
      return rows.map(StopModel.fromMap).toList();
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> upsertStop(StopModel stop) async {
    try {
      final db = await appDatabase.database;

      // UPDATE-depois-INSERT em vez de `ConflictAlgorithm.replace`.
      //
      // Isso não é preciosismo: `INSERT OR REPLACE` apaga a linha antiga e
      // insere outra. Com `foreign_keys = ON`, esse DELETE dispara o
      // `ON DELETE CASCADE` de `active_route_legs` e o trecho some da rota
      // gravada — ou seja, marcar uma entrega como entregue a removeria do
      // roteiro. Atualizar no lugar preserva a identidade da linha.
      await db.transaction((txn) async {
        final map = stop.toMap();
        final updated = await txn.update(
          'stops',
          map,
          where: 'id = ?',
          whereArgs: [stop.id],
        );
        if (updated == 0) {
          await txn.insert('stops', map);
        }
      });
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> deleteStop(String id) async {
    try {
      final db = await appDatabase.database;
      await db.delete('stops', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<int> deleteCompleted() async {
    try {
      final db = await appDatabase.database;
      return db.delete('stops', where: "status != 'pending'");
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }
}
