import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/services/daily_quota.dart';
import '../../../../core/util/cep_formatter.dart';
import '../../../../core/util/cep_range_resolver.dart';
import '../../domain/entities/address_lookup.dart';
import '../../domain/entities/address_query.dart';
import '../../domain/entities/address_suggestion.dart';
import '../../domain/repositories/address_repository.dart';
import '../datasources/address_local_data_source.dart';
import '../datasources/address_remote_data_source.dart';
import '../datasources/cep_directory_local_data_source.dart';
import '../datasources/geoapify_remote_data_source.dart';

/// Nomes gravados junto da coordenada no cache, para dar para saber de onde
/// cada ponto veio quando um resultado parecer errado.
const _providerGeoapify = 'geoapify';
const _providerNominatim = 'nominatim';

class AddressRepositoryImpl implements AddressRepository {
  /// Nominatim + ViaCEP. O ViaCEP continua sendo o dono da consulta de CEP; o
  /// Nominatim virou plano B do geocoding.
  final AddressRemoteDataSource remoteDataSource;

  /// Fonte principal de coordenadas.
  final GeoapifyRemoteDataSource geoapifyDataSource;

  /// Quantas chamadas ao Geoapify ainda cabem hoje.
  final DailyQuota geoapifyQuota;

  final AddressLocalDataSource localDataSource;
  final CepDirectoryLocalDataSource directoryDataSource;
  final NetworkInfo networkInfo;

  /// Espera entre os degraus da cascata do Nominatim. Injetável só para o
  /// teste não gastar segundos de verdade esperando.
  final Duration _cascadeDelay;

  /// Sugestões já buscadas, por texto.
  ///
  /// Cobre o caso de o usuário apagar uma letra e digitar de novo, e o de
  /// reabrir a tela — em ambos a resposta seria idêntica e a chamada,
  /// desperdício. Vive só enquanto o app está aberto: sugestão é resultado de
  /// busca, não dado do usuário, e não vale ocupar banco.
  final _suggestionMemo = <String, List<AddressSuggestion>>{};

  /// Teto do cache de sugestões. Um dia inteiro digitando endereços encheria
  /// isso sem limite.
  static const _memoLimit = 60;

  /// Abaixo disso a busca devolve o Brasil inteiro e nenhuma sugestão presta —
  /// só queimaria cota.
  static const _minSuggestLength = 4;

  AddressRepositoryImpl({
    required this.remoteDataSource,
    required this.geoapifyDataSource,
    required this.geoapifyQuota,
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

  /// Sugestões do Geoapify, com duas economias antes de qualquer chamada: o
  /// texto curto demais nem é consultado, e o texto repetido sai da memória.
  ///
  /// Não há plano B aqui. O Nominatim proíbe uso para autocomplete na própria
  /// política de uso, e ignorar isso levaria o app inteiro a ser bloqueado —
  /// inclusive o geocoding, que é o que realmente importa. Sem Geoapify, o
  /// usuário digita o endereço à mão, como sempre pôde.
  @override
  Future<List<AddressSuggestion>> suggest(String text, {GeoPoint? bias}) async {
    final trimmed = text.trim();
    if (trimmed.length < _minSuggestLength) return const [];

    final key = AddressLocalDataSourceImpl.buildAddressKey(trimmed);
    final memoized = _suggestionMemo[key];
    if (memoized != null) return memoized;

    if (!geoapifyDataSource.isConfigured) return const [];
    if (!geoapifyQuota.hasRoom) return const [];
    if (!await networkInfo.isConnected) return const [];

    try {
      final suggestions =
          await geoapifyDataSource.autocomplete(trimmed, bias: bias);
      await geoapifyQuota.spend();
      _memoize(key, suggestions);
      return suggestions;
    } catch (_) {
      // Autocomplete é conveniência. Falhar em silêncio e deixar o usuário
      // digitar é melhor que interromper o cadastro com um erro.
      return const [];
    }
  }

  void _memoize(String key, List<AddressSuggestion> suggestions) {
    if (_suggestionMemo.length >= _memoLimit) {
      _suggestionMemo.remove(_suggestionMemo.keys.first);
    }
    _suggestionMemo[key] = suggestions;
  }

  @override
  Future<void> rememberSuggestion(AddressSuggestion suggestion) async {
    await _cacheLocationQuietly(
      AddressLocalDataSourceImpl.buildAddressKey(suggestion.query.fullText),
      ApproximateLocation(
        point: suggestion.point,
        precision: suggestion.precision,
      ),
      _providerGeoapify,
    );
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

    // Endereço repetido não precisa de rede. É o corte mais eficaz que existe
    // aqui: entregador roda a mesma região todo dia.
    final cacheKey = AddressLocalDataSourceImpl.buildAddressKey(query.fullText);
    final cached = await _cachedLocation(cacheKey);
    if (cached != null) return cached;

    // Sem rua, o CEP já é o mais específico possível: a base local resolve na
    // hora, sem gastar requisição.
    if (!query.hasStreet && cep != null) {
      final local = await _directoryLocation(cep);
      if (local != null) return local;
    }

    if (await networkInfo.isConnected) {
      final found = await _online(query, cep, cacheKey);
      if (found != null) return found;
    }

    // Sem rede, ou nada respondeu: o centroide do CEP ainda coloca o usuário
    // no lugar certo do mapa. É a razão de a base local existir.
    if (cep != null) {
      final local = await _directoryLocation(cep);
      if (local != null) return local;
    }

    return null;
  }

  /// Geoapify primeiro; Nominatim quando ele não está disponível ou não achou.
  ///
  /// O Geoapify virou principal porque o OpenStreetMap não cobre cidade
  /// pequena no Brasil — medido: "Rua Carlos Ollig, Apiaí/SP" não existe lá em
  /// nenhuma forma de consulta, nem pela rua, nem pelo CEP, nem pelo bairro.
  Future<ApproximateLocation?> _online(
    AddressQuery query,
    String? cep,
    String cacheKey,
  ) async {
    if (geoapifyDataSource.isConfigured && geoapifyQuota.hasRoom) {
      try {
        final found = await geoapifyDataSource.geocode(query);
        await geoapifyQuota.spend();

        if (found != null) {
          await _cacheLocationQuietly(cacheKey, found, _providerGeoapify);
          return found;
        }
      } catch (_) {
        // Serviço fora do ar ou chave recusada: continua para o plano B em vez
        // de deixar o usuário sem localização nenhuma.
      }
    }

    final fallback = await _nominatimCascade(query, cep);
    if (fallback != null) {
      await _cacheLocationQuietly(cacheKey, fallback, _providerNominatim);
    }
    return fallback;
  }

  /// Plano B. Cada degrau pede menos que o anterior: número, rua, CEP, bairro,
  /// cidade. Para no primeiro que responder.
  Future<ApproximateLocation?> _nominatimCascade(
    AddressQuery query,
    String? cep,
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
      // Texto livre, e não busca estruturada: o Nominatim não tem campo para
      // bairro, e enfiá-lo em `street` pede uma via com aquele nome — que não
      // existe. Verificado: "Bela Vista, São Paulo" acha o bairro por texto
      // livre e devolve vazio no estruturado.
      if (query.hasNeighborhood && query.hasCity)
        _Attempt(
          LocationPrecision.neighborhood,
          () => remoteDataSource.geocode(
            [
              query.neighborhood!.trim(),
              query.city!.trim(),
              if ((query.state ?? '').trim().isNotEmpty) query.state!.trim(),
              'Brasil',
            ].join(', '),
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

        return ApproximateLocation(point: point, precision: attempt.precision);
      } catch (_) {
        // Esse degrau não respondeu — tenta o próximo, mais amplo.
      }
    }

    return null;
  }

  Future<ApproximateLocation?> _cachedLocation(String key) async {
    try {
      return await localDataSource.getCachedLocation(key);
    } on CacheException {
      return null;
    }
  }

  Future<ApproximateLocation?> _directoryLocation(String cep) async {
    final lookup = await _tryDirectory(cep);
    if (lookup == null || !lookup.hasCoordinate) return null;

    return ApproximateLocation(
      point: lookup.coordinate!,
      precision: LocationPrecision.postalCode,
    );
  }

  @override
  Future<GeoPoint?> coordinateFromDirectory(String cep) async {
    final normalized = CepFormatter.normalize(cep);
    if (!CepFormatter.isValid(normalized)) return null;

    final lookup = await _tryDirectory(normalized);
    return lookup?.hasCoordinate ?? false ? lookup!.coordinate : null;
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

  Future<void> _cacheLocationQuietly(
    String key,
    ApproximateLocation location,
    String provider,
  ) async {
    try {
      await localDataSource.cacheLocation(key, location, provider: provider);
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
