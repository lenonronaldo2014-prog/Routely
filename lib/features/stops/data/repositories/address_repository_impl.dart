import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/util/cep_formatter.dart';
import '../../../../core/util/cep_range_resolver.dart';
import '../../domain/entities/address_lookup.dart';
import '../../domain/repositories/address_repository.dart';
import '../datasources/address_local_data_source.dart';
import '../datasources/address_remote_data_source.dart';
import '../datasources/cep_directory_local_data_source.dart';

class AddressRepositoryImpl implements AddressRepository {
  final AddressRemoteDataSource remoteDataSource;
  final AddressLocalDataSource localDataSource;
  final CepDirectoryLocalDataSource directoryDataSource;
  final NetworkInfo networkInfo;

  AddressRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.directoryDataSource,
    required this.networkInfo,
  });

  /// Ordem de consulta, do mais barato e confiável para o mais caro:
  ///
  /// 1. **base local do estado** — instantânea, funciona sem rede, cobre CEPs
  ///    nunca vistos antes. É o que torna o offline uma promessa real e não
  ///    só "funciona pro que você já usou";
  /// 2. **cache** — CEPs já consultados neste aparelho;
  /// 3. **rede** (ViaCEP);
  /// 4. **faixa numérica** — último recurso, devolve só a UF. Melhor que uma
  ///    tela de erro: o usuário completa o resto na mão e segue trabalhando.
  @override
  Future<Either<Failure, AddressLookup>> lookupCep(String cep) async {
    final normalized = CepFormatter.normalize(cep);
    if (!CepFormatter.isValid(normalized)) {
      return Left(GeocodingFailure('CEP precisa ter 8 dígitos.'));
    }

    final fromDirectory = await _tryDirectory(normalized);
    if (fromDirectory != null) return Right(fromDirectory);

    final cached = await _tryCache(normalized);
    if (cached != null) return Right(cached);

    if (await networkInfo.isConnected) {
      final remote = await _tryRemote(normalized);
      if (remote != null) return remote;
    }

    return _rangeFallback(normalized);
  }

  Future<AddressLookup?> _tryDirectory(String cep) async {
    try {
      return await directoryDataSource.lookup(cep);
    } on CacheException {
      // Base corrompida ou ausente não pode derrubar a consulta.
      return null;
    }
  }

  Future<AddressLookup?> _tryCache(String cep) async {
    try {
      return await localDataSource.getCachedCep(cep);
    } on CacheException {
      return null;
    }
  }

  /// Devolve null quando a rede falhou de um jeito que vale tentar a faixa;
  /// devolve `Left` quando o CEP existe mas é inválido — aí insistir não ajuda.
  Future<Either<Failure, AddressLookup>?> _tryRemote(String cep) async {
    try {
      final lookup = await remoteDataSource.lookupCep(cep);
      await _cacheCepQuietly(lookup);
      return Right(lookup);
    } on GeocodingException catch (e) {
      // O ViaCEP respondeu que este CEP não existe. Isso é informação, não
      // falha de rede — a faixa numérica não vai melhorar nada.
      return Left(GeocodingFailure(e.message));
    } on ServerException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Either<Failure, AddressLookup> _rangeFallback(String cep) {
    final uf = CepRangeResolver.ufFor(cep);
    if (uf == null) {
      return Left(ConnectionFailure());
    }

    return Right(AddressLookup(
      cep: cep,
      street: '',
      neighborhood: '',
      city: '',
      state: uf,
      source: AddressSource.cepRange,
    ));
  }

  @override
  Future<GeoPoint?> coordinateFromDirectory(String cep) async {
    final normalized = CepFormatter.normalize(cep);
    if (!CepFormatter.isValid(normalized)) return null;

    final lookup = await _tryDirectory(normalized);
    return lookup?.hasCoordinate ?? false ? lookup!.coordinate : null;
  }

  @override
  Future<Either<Failure, GeoPoint>> geocode(String fullAddress) async {
    final key = AddressLocalDataSourceImpl.buildAddressKey(fullAddress);

    try {
      final cached = await localDataSource.getCachedGeocode(key);
      if (cached != null) return Right(cached);
    } on CacheException {
      // Segue para a rede.
    }

    if (!await networkInfo.isConnected) {
      return Left(ConnectionFailure());
    }

    try {
      final point = await remoteDataSource.geocode(fullAddress);
      await _cacheGeocodeQuietly(key, point);
      return Right(point);
    } on GeocodingException catch (e) {
      return Left(GeocodingFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(statusCode: e.statusCode));
    } catch (_) {
      return Left(ConnectionFailure());
    }
  }

  /// Gravar no cache é oportunista: se falhar, o usuário já tem o resultado e
  /// não deve ver erro por causa disso.
  Future<void> _cacheCepQuietly(AddressLookup lookup) async {
    try {
      await localDataSource.cacheCep(lookup);
    } on CacheException {
      // Ignorado de propósito.
    }
  }

  Future<void> _cacheGeocodeQuietly(String key, GeoPoint point) async {
    try {
      await localDataSource.cacheGeocode(key, point);
    } on CacheException {
      // Ignorado de propósito.
    }
  }
}
