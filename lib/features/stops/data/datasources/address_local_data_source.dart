import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/geo/geo_point.dart';
import '../../domain/entities/address_lookup.dart';

/// Cache local de CEP e de geocoding.
///
/// Não é otimização opcional: é o que sustenta as duas promessas centrais do
/// app. Entregador autônomo trabalha em região fixa e repete endereço o tempo
/// todo, então depois de alguns dias de uso a maior parte das consultas nem
/// sai do aparelho — o que corta custo de API e faz o cadastro funcionar sem
/// rede.
abstract class AddressLocalDataSource {
  Future<AddressLookup?> getCachedCep(String cep);
  Future<void> cacheCep(AddressLookup lookup);
  Future<GeoPoint?> getCachedGeocode(String addressKey);
  Future<void> cacheGeocode(String addressKey, GeoPoint point);
}

class AddressLocalDataSourceImpl implements AddressLocalDataSource {
  final AppDatabase appDatabase;

  AddressLocalDataSourceImpl({required this.appDatabase});

  /// Normaliza o endereço para chave de cache: minúsculas, sem espaço extra.
  /// Assim "Rua X, 10 - Centro" e "rua x,  10 - centro" batem no mesmo registro.
  static String buildAddressKey(String fullAddress) =>
      fullAddress.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  Future<AddressLookup?> getCachedCep(String cep) async {
    try {
      final db = await appDatabase.database;
      final rows = await db.query(
        'cep_cache',
        where: 'cep = ?',
        whereArgs: [cep],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final row = rows.first;
      return AddressLookup(
        cep: row['cep'] as String,
        street: (row['street'] as String?) ?? '',
        neighborhood: (row['neighborhood'] as String?) ?? '',
        city: (row['city'] as String?) ?? '',
        state: (row['state'] as String?) ?? '',
        source: AddressSource.cache,
      );
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> cacheCep(AddressLookup lookup) async {
    try {
      final db = await appDatabase.database;
      await db.insert(
        'cep_cache',
        {
          'cep': lookup.cep.replaceAll(RegExp(r'\D'), ''),
          'street': lookup.street,
          'neighborhood': lookup.neighborhood,
          'city': lookup.city,
          'state': lookup.state,
          'cached_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<GeoPoint?> getCachedGeocode(String addressKey) async {
    try {
      final db = await appDatabase.database;
      final rows = await db.query(
        'geocode_cache',
        where: 'address_key = ?',
        whereArgs: [addressKey],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      return GeoPoint(
        latitude: rows.first['latitude'] as double,
        longitude: rows.first['longitude'] as double,
      );
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> cacheGeocode(String addressKey, GeoPoint point) async {
    try {
      final db = await appDatabase.database;
      await db.insert(
        'geocode_cache',
        {
          'address_key': addressKey,
          'latitude': point.latitude,
          'longitude': point.longitude,
          'cached_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }
}
