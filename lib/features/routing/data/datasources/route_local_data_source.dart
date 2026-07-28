import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/geo/geo_point.dart';
import '../../../stops/data/models/stop_model.dart';
import '../../../stops/domain/entities/delivery_stop.dart';
import '../../domain/entities/active_route.dart';
import '../../domain/entities/route_option.dart';
import '../../domain/entities/route_strategy.dart';

abstract class RouteLocalDataSource {
  Future<void> saveActiveRoute(ActiveRoute route);

  /// Retorna null quando não há rota em andamento.
  Future<ActiveRoute?> getActiveRoute();

  Future<void> clearActiveRoute();
}

class RouteLocalDataSourceImpl implements RouteLocalDataSource {
  final AppDatabase appDatabase;

  RouteLocalDataSourceImpl({required this.appDatabase});

  @override
  Future<void> saveActiveRoute(ActiveRoute route) async {
    try {
      final db = await appDatabase.database;

      // Transação: uma rota meio salva — cabeçalho sem trechos — deixaria o
      // app num estado impossível de exibir.
      await db.transaction((txn) async {
        await txn.delete('active_route_legs');
        await txn.delete('active_route');

        await txn.insert('active_route', {
          'id': 1,
          'strategy': route.strategy.name,
          'origin_latitude': route.origin.latitude,
          'origin_longitude': route.origin.longitude,
          'travel_seconds': route.travelDurationSeconds,
          'service_seconds': route.serviceDurationSeconds,
          'distance_meters': route.totalDistanceMeters,
          'is_estimate': route.isEstimate ? 1 : 0,
          'started_at': route.startedAt.millisecondsSinceEpoch,
        });

        for (var i = 0; i < route.legs.length; i++) {
          final leg = route.legs[i];
          await txn.insert('active_route_legs', {
            'position': i,
            'stop_id': leg.to.id,
            'distance_meters': leg.distanceMeters,
            'duration_seconds': leg.durationSeconds,
          });
        }
      });
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<ActiveRoute?> getActiveRoute() async {
    try {
      final db = await appDatabase.database;

      final header = await db.query('active_route', limit: 1);
      if (header.isEmpty) return null;

      final row = header.first;

      // Junta com stops para trazer o endereço e o status atuais — a rota
      // guarda só os ids, então marcar entregue ou editar endereço reflete
      // aqui sem sincronização manual.
      final legRows = await db.rawQuery('''
        SELECT l.position, l.distance_meters, l.duration_seconds, s.*
        FROM active_route_legs l
        INNER JOIN stops s ON s.id = l.stop_id
        ORDER BY l.position ASC
      ''');

      // Todas as paradas sumiram (usuário apagou tudo): a rota não existe mais.
      if (legRows.isEmpty) {
        await clearActiveRoute();
        return null;
      }

      final legs = <RouteLeg>[];
      DeliveryStop? previous;

      for (final legRow in legRows) {
        final stop = StopModel.fromMap(legRow);
        legs.add(RouteLeg(
          from: previous,
          to: stop,
          distanceMeters: legRow['distance_meters'] as double,
          durationSeconds: legRow['duration_seconds'] as double,
        ));
        previous = stop;
      }

      return ActiveRoute(
        strategy: RouteStrategy.values.firstWhere(
          (s) => s.name == row['strategy'],
          orElse: () => RouteStrategy.fastest,
        ),
        origin: GeoPoint(
          latitude: row['origin_latitude'] as double,
          longitude: row['origin_longitude'] as double,
        ),
        legs: legs,
        travelDurationSeconds: row['travel_seconds'] as double,
        serviceDurationSeconds: row['service_seconds'] as double,
        totalDistanceMeters: row['distance_meters'] as double,
        isEstimate: (row['is_estimate'] as int) == 1,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int),
      );
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> clearActiveRoute() async {
    try {
      final db = await appDatabase.database;
      await db.transaction((txn) async {
        await txn.delete('active_route_legs');
        await txn.delete('active_route');
      });
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }
}
