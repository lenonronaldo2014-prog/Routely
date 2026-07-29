import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/geo/geo_point.dart';
import '../../domain/entities/address_lookup.dart';
import '../../domain/entities/address_query.dart';

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

  /// Coordenada já resolvida para este endereço, com a precisão que ela tinha
  /// quando foi obtida.
  ///
  /// É o que evita pagar duas vezes pelo mesmo endereço: entregador repete
  /// muito destino, e a segunda consulta traria exatamente a mesma resposta da
  /// primeira.
  Future<ApproximateLocation?> getCachedLocation(String addressKey);

  Future<void> cacheLocation(
    String addressKey,
    ApproximateLocation location, {
    required String provider,
  });
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
  Future<ApproximateLocation?> getCachedLocation(String addressKey) async {
    try {
      final db = await appDatabase.database;
      final rows = await db.query(
        'geocode_cache',
        where: 'address_key = ?',
        whereArgs: [addressKey],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final row = rows.first;
      final point = GeoPoint(
        latitude: row['latitude'] as double,
        longitude: row['longitude'] as double,
      );

      return ApproximateLocation(
        point: point,
        precision: _precisionFrom(row['precision'] as String?),
      );
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> cacheLocation(
    String addressKey,
    ApproximateLocation location, {
    required String provider,
  }) async {
    try {
      final db = await appDatabase.database;
      await db.insert(
        'geocode_cache',
        {
          'address_key': addressKey,
          'latitude': location.point.latitude,
          'longitude': location.point.longitude,
          'precision': location.precision.name,
          'provider': provider,
          'cached_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  /// Linhas gravadas antes da coluna existir não têm precisão. Na versão
  /// anterior o cache só recebia acerto exato, então ler o nulo como exato
  /// preserva o significado do que já estava lá.
  static LocationPrecision _precisionFrom(String? name) =>
      LocationPrecision.values.firstWhere(
        (precision) => precision.name == name,
        orElse: () => LocationPrecision.exact,
      );
}
