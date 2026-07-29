import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/util/cep_formatter.dart';
import '../../../../core/util/cep_range_resolver.dart';
import '../../domain/entities/address_lookup.dart';
import '../../domain/entities/address_query.dart';
import '../../domain/repositories/address_repository.dart';
import '../datasources/address_local_data_source.dart';
import '../datasources/address_remote_data_source.dart';
import '../datasources/cep_directory_local_data_source.dart';

class AddressRepositoryImpl implements AddressRepository {
  final AddressRemoteDataSource remoteDataSource;
  final AddressLocalDataSource localDataSource;
  final CepDirectoryLocalDataSource directoryDataSource;
  final NetworkInfo networkInfo;

  /// Espera entre os degraus da cascata. Injetável só para o teste não gastar
  /// segundos de verdade esperando.
  final Duration _cascadeDelay;

  AddressRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.directoryDataSource,
    required this.networkInfo,
    Duration cascadeDelay = const Duration(seconds: 1),
  }) : _cascadeDelay = cascadeDelay;

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

  /// Vai afrouxando a busca até algo responder, e conta em que degrau parou.
  ///
  /// Antes daqui, um endereço não encontrado caía na localização do próprio
  /// usuário — que podia estar a quilômetros. Errar por 200m dentro do bairro
  /// certo é outra história: ele arrasta o pin e segue.
  @override
  Future<ApproximateLocation?> locateApproximate(AddressQuery query) async {
    if (query.isEmpty) return null;

    final cep = query.normalizedCep;

    // Endereço repetido não precisa de rede. Só o resultado exato é guardado,
    // então um acerto no cache é sempre exato — nunca um bairro se passando
    // por porta.
    final cacheKey = AddressLocalDataSourceImpl.buildAddressKey(query.fullText);
    final cached = await _cachedGeocode(cacheKey);
    if (cached != null) {
      return ApproximateLocation(
        point: cached,
        precision: LocationPrecision.exact,
      );
    }

    // Sem rua, o CEP já é o mais específico possível: a base local resolve na
    // hora, sem gastar requisição.
    if (!query.hasStreet && cep != null) {
      final local = await _directoryPoint(cep);
      if (local != null) {
        return ApproximateLocation(
          point: local,
          precision: LocationPrecision.postalCode,
        );
      }
    }

    if (await networkInfo.isConnected) {
      final found = await _geocodeCascade(query, cep, cacheKey);
      if (found != null) return found;
    }

    // Sem rede, ou nada respondeu: o centroide do CEP ainda coloca o usuário
    // no lugar certo do mapa. É a razão de a base local existir.
    if (cep != null) {
      final local = await _directoryPoint(cep);
      if (local != null) {
        return ApproximateLocation(
          point: local,
          precision: LocationPrecision.postalCode,
        );
      }
    }

    return null;
  }

  /// Cada degrau pede menos ao geocoder que o anterior: número, rua, CEP,
  /// bairro, cidade. Para no primeiro que responder.
  Future<ApproximateLocation?> _geocodeCascade(
    AddressQuery query,
    String? cep,
    String cacheKey,
  ) async {
    final hasNumber = (query.number ?? '').trim().isNotEmpty;

    final attempts = <_Attempt>[
      if (query.hasStreet && hasNumber)
        _Attempt(
          LocationPrecision.exact,
          () => remoteDataSource.geocode(query.fullText),
        ),
      if (query.hasStreet)
        _Attempt(
          LocationPrecision.street,
          () => remoteDataSource.geocodeStructured(
            street: query.street,
            city: query.city,
            state: query.state,
          ),
        ),
      if (cep != null)
        _Attempt(
          LocationPrecision.postalCode,
          () => remoteDataSource.geocodeStructured(postalCode: cep),
        ),
      if (query.hasNeighborhood && query.hasCity)
        _Attempt(
          LocationPrecision.neighborhood,
          () => remoteDataSource.geocodeStructured(
            street: query.neighborhood,
            city: query.city,
            state: query.state,
          ),
        ),
      if (query.hasCity)
        _Attempt(
          LocationPrecision.city,
          () => remoteDataSource.geocodeStructured(
            city: query.city,
            state: query.state,
          ),
        ),
    ];

    for (var i = 0; i < attempts.length; i++) {
      // O Nominatim pede no máximo uma consulta por segundo. Disparar a
      // cascata inteira de uma vez é o caminho curto para levar bloqueio.
      if (i > 0) await Future<void>.delayed(_cascadeDelay);

      final attempt = attempts[i];
      try {
        final point = await attempt.run();
        if (!point.isValid) continue;

        if (attempt.precision == LocationPrecision.exact) {
          await _cacheGeocodeQuietly(cacheKey, point);
        }

        return ApproximateLocation(point: point, precision: attempt.precision);
      } catch (_) {
        // Esse degrau não respondeu — tenta o próximo, mais amplo.
      }
    }

    return null;
  }

  Future<GeoPoint?> _cachedGeocode(String key) async {
    try {
      return await localDataSource.getCachedGeocode(key);
    } on CacheException {
      return null;
    }
  }

  Future<GeoPoint?> _directoryPoint(String cep) async {
    final lookup = await _tryDirectory(cep);
    if (lookup == null || !lookup.hasCoordinate) return null;

    final point = lookup.coordinate;
    return point != null && point.isValid ? point : null;
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

/// Um degrau da cascata: o que buscar e quanta precisão o acerto representa.
class _Attempt {
  final LocationPrecision precision;
  final Future<GeoPoint> Function() run;

  _Attempt(this.precision, this.run);
}
