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
      final found = await _geoapify(query);
      if (found != null) {
        await _remember(cacheKey, found, _providerGeoapify);
        return found;
      }
    }

    final fallback = await _nominatimCascade(query, cep);
    if (fallback != null) {
      await _remember(cacheKey, fallback, _providerNominatim);
    }
    return fallback;
  }

  /// Guarda o resultado — desde que ele valha a pena ser lembrado.
  ///
  /// Acerto no bairro ou na cidade não entra no cache. Um resultado desses não
  /// é uma resposta, é uma desistência, e gravá-lo congela a desistência: o
  /// endereço nunca mais seria consultado, mesmo depois de o app melhorar ou
  /// de o provedor ganhar o dado.
  ///
  /// Foi exatamente o que aconteceu ao corrigir a repetição sem número. A
  /// correção só teve efeito depois de limpar os dados do app, porque o
  /// resultado antigo, de nível cidade, continuava saindo do cache.
  ///
  /// O custo de não guardar é baixo: são justamente os casos em que o usuário
  /// acaba marcando o ponto no mapa, e aí a coordenada fica gravada na parada
  /// e nenhuma consulta acontece de novo.
  Future<void> _remember(
    String key,
    ApproximateLocation location,
    String provider,
  ) async {
    if (_tooCoarse(location.precision)) return;
    await _cacheLocationQuietly(key, location, provider);
  }

  /// Consulta o Geoapify, repetindo sem o número quando ele estraga a busca.
  ///
  /// Um número que não consta na base não faz o Geoapify parar na rua: ele
  /// desiste do endereço inteiro e devolve a **cidade**. Medido com
  /// "Rua Carlos Olig, Apiaí/SP":
  ///
  ///   nº 20          -> building, na porta
  ///   nº 73          -> city, a 1,6 km  (o 73 não existe naquela rua)
  ///   sem número     -> street, em cima da rua
  ///
  /// Aceitar o primeiro resultado jogaria o usuário no centro da cidade tendo
  /// a rua certa disponível. A segunda chamada só acontece quando a primeira
  /// degradou a esse ponto, então o custo extra é raro.
  Future<ApproximateLocation?> _geoapify(AddressQuery query) async {
    final first = await _geoapifyAttempt(query);
    if (first != null && !_tooCoarse(first.precision)) return first;

    final hasNumber = (query.number ?? '').trim().isNotEmpty;
    if (!hasNumber || !query.hasStreet) return first;
    if (!geoapifyQuota.hasRoom) return first;

    final retry = await _geoapifyAttempt(query.withoutNumber());
    if (retry == null) return first;

    // Fica com o melhor dos dois. A repetição normalmente ganha, mas se ela
    // vier pior ainda, o primeiro resultado continua valendo.
    if (first == null) return retry;
    return retry.precision.index < first.precision.index ? retry : first;
  }

  Future<ApproximateLocation?> _geoapifyAttempt(AddressQuery query) async {
    try {
      final found = await geoapifyDataSource.geocode(query);
      await geoapifyQuota.spend();
      return found;
    } catch (_) {
      // Serviço fora do ar ou chave recusada: devolve nada e deixa o plano B
      // assumir, em vez de o usuário ficar sem localização nenhuma.
      return null;
    }
  }

  /// Grosseira a ponto de valer outra chamada: bairro ou cidade.
  ///
  /// Rua e CEP não entram. Os dois caem no mesmo quarteirão, e repetir a
  /// consulta gastaria cota para trocar um resultado bom por outro parecido.
  ///
  /// `LocationPrecision` está declarada da mais fina para a mais grosseira, o
  /// que faz o índice servir de ordenação.
  static bool _tooCoarse(LocationPrecision precision) =>
      precision.index > LocationPrecision.postalCode.index;

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
