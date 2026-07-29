import 'package:flutter_test/flutter_test.dart';
import 'package:routely/core/error/exceptions.dart';
import 'package:routely/core/geo/geo_point.dart';
import 'package:routely/core/network/network_info.dart';
import 'package:routely/core/services/daily_quota.dart';
import 'package:routely/features/stops/data/datasources/address_local_data_source.dart';
import 'package:routely/features/stops/data/datasources/address_remote_data_source.dart';
import 'package:routely/features/stops/data/datasources/cep_directory_local_data_source.dart';
import 'package:routely/features/stops/data/datasources/geoapify_remote_data_source.dart';
import 'package:routely/features/stops/data/repositories/address_repository_impl.dart';
import 'package:routely/features/stops/domain/entities/address_lookup.dart';
import 'package:routely/features/stops/domain/entities/address_query.dart';
import 'package:routely/features/stops/domain/entities/address_suggestion.dart';
import 'package:routely/features/stops/domain/entities/cep_pack.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Endereço real de cidade pequena que o OpenStreetMap não mapeia: nem a rua,
/// nem o CEP, nem o bairro respondem. Foi o caso que expôs o problema — antes
/// da cascata o app desistia e abria o mapa na localização do usuário, que
/// podia estar do outro lado do estado.
const _query = AddressQuery(
  cep: '18320-620',
  street: 'Rua Carlos Ollig',
  number: '20',
  neighborhood: 'Pinheiros',
  city: 'Apiaí',
  state: 'SP',
);

const _found = GeoPoint(latitude: -24.50765, longitude: -48.84616);

/// Geocoder que só responde às buscas listadas em [answers]; qualquer outra
/// levanta exceção, como o Nominatim faz quando não acha nada.
class _FakeRemote implements AddressRemoteDataSource {
  /// Rótulo de cada chamada recebida, na ordem. É o que prova que a busca foi
  /// afrouxando degrau por degrau em vez de pular direto para o mais amplo.
  final calls = <String>[];

  /// Rótulos que devem responder com sucesso.
  final Set<String> answers;

  _FakeRemote(this.answers);

  @override
  Future<AddressLookup> lookupCep(String cep) async =>
      throw UnimplementedError();

  /// Texto livre serve a dois degraus: o endereço com número e o bairro. O
  /// que os separa é o número aparecer ou não na frase.
  @override
  Future<GeoPoint> geocode(String fullAddress) async =>
      _reply(fullAddress.contains(_query.number!) ? 'freeText' : 'neighborhood');

  @override
  Future<GeoPoint> geocodeStructured({
    String? street,
    String? city,
    String? state,
    String? postalCode,
  }) async {
    if (postalCode != null) return _reply('postalCode');
    if (street != null && street.isNotEmpty) return _reply('street');
    return _reply('city');
  }

  GeoPoint _reply(String label) {
    calls.add(label);
    if (!answers.contains(label)) {
      throw GeocodingException('Endereço não localizado no mapa.');
    }
    return _found;
  }
}

/// Nunca acha nada, mas guarda como cada degrau foi perguntado. Serve para
/// checar a forma da consulta, não o resultado.
class _SpyRemote implements AddressRemoteDataSource {
  final freeTextQueries = <String>[];
  final structuredStreets = <String>[];

  @override
  Future<AddressLookup> lookupCep(String cep) async =>
      throw UnimplementedError();

  @override
  Future<GeoPoint> geocode(String fullAddress) async {
    freeTextQueries.add(fullAddress);
    throw GeocodingException('nada');
  }

  @override
  Future<GeoPoint> geocodeStructured({
    String? street,
    String? city,
    String? state,
    String? postalCode,
  }) async {
    if (street != null) structuredStreets.add(street);
    throw GeocodingException('nada');
  }
}

class _FakeCache implements AddressLocalDataSource {
  final Map<String, ApproximateLocation> locations = {};
  final Map<String, String> providers = {};

  @override
  Future<AddressLookup?> getCachedCep(String cep) async => null;

  @override
  Future<void> cacheCep(AddressLookup lookup) async {}

  @override
  Future<ApproximateLocation?> getCachedLocation(String addressKey) async =>
      locations[addressKey];

  @override
  Future<void> cacheLocation(
    String addressKey,
    ApproximateLocation location, {
    required String provider,
  }) async {
    locations[addressKey] = location;
    providers[addressKey] = provider;
  }
}

/// Geoapify controlável: responde o que estiver em [answer], ou nada.
class _FakeGeoapify implements GeoapifyRemoteDataSource {
  final ApproximateLocation? answer;
  final List<AddressSuggestion> suggestions;
  final bool configured;

  /// Se deve estourar em vez de responder — para checar que o plano B entra.
  final bool fails;

  int geocodeCalls = 0;
  int autocompleteCalls = 0;

  _FakeGeoapify({
    this.answer,
    this.suggestions = const [],
    this.configured = true,
    this.fails = false,
  });

  @override
  bool get isConfigured => configured;

  @override
  Future<ApproximateLocation?> geocode(AddressQuery query) async {
    geocodeCalls++;
    if (fails) throw GeocodingException('fora do ar');
    return answer;
  }

  @override
  Future<List<AddressSuggestion>> autocomplete(
    String text, {
    GeoPoint? bias,
  }) async {
    autocompleteCalls++;
    if (fails) throw GeocodingException('fora do ar');
    return suggestions;
  }
}

class _FakeDirectory implements CepDirectoryLocalDataSource {
  final GeoPoint? coordinate;

  _FakeDirectory({this.coordinate});

  @override
  Future<AddressLookup?> lookup(String cep) async {
    if (coordinate == null) return null;
    return AddressLookup(
      cep: cep,
      street: 'Rua Carlos Ollig',
      neighborhood: 'Pinheiros',
      city: 'Apiaí',
      state: 'SP',
      coordinate: coordinate,
      source: AddressSource.localDirectory,
    );
  }

  @override
  Future<int> importState({
    required String state,
    required Stream<String> lines,
    String? sourceVersion,
    void Function(CepImportProgress progress)? onProgress,
  }) async =>
      0;

  @override
  Future<List<CepPack>> installedPacks() async => [];

  @override
  Future<void> removeState(String state) async {}
}

class _FakeNetwork implements NetworkInfo {
  final bool connected;

  _FakeNetwork(this.connected);

  @override
  Future<bool> get isConnected async => connected;
}

late SharedPreferences _prefs;

/// `budget: 0` representa a cota do dia esgotada — é o que faz o app cair no
/// plano B.
DailyQuota _quota({int budget = 100}) =>
    DailyQuota(prefs: _prefs, name: 'geoapify', budget: budget);

AddressRepositoryImpl _repository({
  required AddressRemoteDataSource remote,
  _FakeGeoapify? geoapify,
  DailyQuota? quota,
  _FakeCache? cache,
  GeoPoint? directoryPoint,
  bool connected = true,
}) =>
    AddressRepositoryImpl(
      remoteDataSource: remote,
      // Sem Geoapify por padrão: a maioria dos testes exercita a cascata do
      // Nominatim, que é o plano B.
      geoapifyDataSource: geoapify ?? _FakeGeoapify(configured: false),
      geoapifyQuota: quota ?? _quota(),
      localDataSource: cache ?? _FakeCache(),
      directoryDataSource: _FakeDirectory(coordinate: directoryPoint),
      networkInfo: _FakeNetwork(connected),
      // Sem isso cada teste esperaria segundos reais entre os degraus.
      cascadeDelay: Duration.zero,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  group('locateApproximate', () {
    test('endereço completo encontrado devolve precisão exata', () async {
      final remote = _FakeRemote({'freeText'});
      final result = await _repository(remote: remote).locateApproximate(_query);

      expect(result?.precision, LocationPrecision.exact);
      expect(result?.point, _found);
      expect(remote.calls, ['freeText'], reason: 'não deveria afrouxar à toa');
    });

    test('número não encontrado cai para a rua', () async {
      final remote = _FakeRemote({'street'});
      final result = await _repository(remote: remote).locateApproximate(_query);

      expect(result?.precision, LocationPrecision.street);
      expect(remote.calls, ['freeText', 'street']);
    });

    test('rua desconhecida cai para o CEP', () async {
      final remote = _FakeRemote({'postalCode'});
      final result = await _repository(remote: remote).locateApproximate(_query);

      expect(result?.precision, LocationPrecision.postalCode);
      expect(remote.calls, ['freeText', 'street', 'postalCode']);
    });

    test('sem CEP no mapa, o bairro ainda serve', () async {
      final remote = _FakeRemote({'neighborhood'});
      final result = await _repository(remote: remote).locateApproximate(_query);

      expect(result?.precision, LocationPrecision.neighborhood);
      expect(remote.calls, ['freeText', 'street', 'postalCode', 'neighborhood']);
    });

    // O Nominatim não tem campo para bairro. Pedir bairro em `street` faz ele
    // procurar uma via com aquele nome e devolver vazio — verificado contra o
    // serviço real: "Bela Vista, São Paulo" acha por texto livre e não acha
    // no estruturado. Este teste existe para o degrau não voltar a ser
    // estruturado por parecer mais organizado.
    test('o bairro é buscado por texto livre, não estruturado', () async {
      final remote = _SpyRemote();
      await _repository(remote: remote).locateApproximate(_query);

      expect(
        remote.freeTextQueries,
        contains('Pinheiros, Apiaí, SP, Brasil'),
      );
      expect(
        remote.structuredStreets,
        isNot(contains('Pinheiros')),
        reason: 'bairro no campo street pede uma via, e não acha nada',
      );
    });

    test('último recurso é a cidade', () async {
      final remote = _FakeRemote({'city'});
      final result = await _repository(remote: remote).locateApproximate(_query);

      expect(result?.precision, LocationPrecision.city);
      expect(remote.calls.last, 'city');
    });

    test('nada encontrado devolve null, para a tela cair no GPS', () async {
      final remote = _FakeRemote({});
      final result = await _repository(remote: remote).locateApproximate(_query);

      expect(result, isNull);
    });

    test('base local resolve sem tocar na rede quando não há rua', () async {
      final remote = _FakeRemote({'freeText'});
      final result = await _repository(
        remote: remote,
        directoryPoint: _found,
      ).locateApproximate(const AddressQuery(cep: '18320620'));

      expect(result?.precision, LocationPrecision.postalCode);
      expect(remote.calls, isEmpty);
    });

    test('offline, o centroide do CEP ainda coloca no lugar certo', () async {
      final remote = _FakeRemote({'freeText'});
      final result = await _repository(
        remote: remote,
        directoryPoint: _found,
        connected: false,
      ).locateApproximate(_query);

      expect(result?.precision, LocationPrecision.postalCode);
      expect(remote.calls, isEmpty, reason: 'sem rede, não se tenta a rede');
    });

    test('offline e sem base instalada devolve null', () async {
      final remote = _FakeRemote({'freeText'});
      final result = await _repository(remote: remote, connected: false)
          .locateApproximate(_query);

      expect(result, isNull);
    });

    // O cache guarda a precisão junto. Sem isso, um acerto de bairro voltaria
    // do cache se passando por endereço exato e o usuário confirmaria um ponto
    // errado achando que estava conferido.
    test('o cache preserva a precisão do resultado', () async {
      final cache = _FakeCache();
      await _repository(remote: _FakeRemote({'street'}), cache: cache)
          .locateApproximate(_query);

      final remote = _FakeRemote({'freeText'});
      final result = await _repository(remote: remote, cache: cache)
          .locateApproximate(_query);

      expect(result?.precision, LocationPrecision.street);
      expect(remote.calls, isEmpty, reason: 'veio do cache');
    });

    test('endereço repetido sai do cache sem tocar na rede', () async {
      final cache = _FakeCache();
      await _repository(remote: _FakeRemote({'freeText'}), cache: cache)
          .locateApproximate(_query);

      final remote = _FakeRemote({'freeText'});
      final result = await _repository(remote: remote, cache: cache)
          .locateApproximate(_query);

      expect(result?.precision, LocationPrecision.exact);
      expect(remote.calls, isEmpty);
    });

    test('consulta vazia não gasta requisição', () async {
      final remote = _FakeRemote({'freeText'});
      final result = await _repository(remote: remote)
          .locateApproximate(const AddressQuery());

      expect(result, isNull);
      expect(remote.calls, isEmpty);
    });
  });

  group('Geoapify como fonte principal', () {
    const geoapifyPoint = GeoPoint(latitude: -24.5100, longitude: -48.8400);
    const exact = ApproximateLocation(
      point: geoapifyPoint,
      precision: LocationPrecision.exact,
    );

    test('acertou: o Nominatim nem é consultado', () async {
      final remote = _FakeRemote({'freeText'});
      final geoapify = _FakeGeoapify(answer: exact);

      final result = await _repository(remote: remote, geoapify: geoapify)
          .locateApproximate(_query);

      expect(result?.point, geoapifyPoint);
      expect(geoapify.geocodeCalls, 1);
      expect(remote.calls, isEmpty, reason: 'plano B só entra quando falta');
    });

    test('não achou: cai para a cascata do Nominatim', () async {
      final remote = _FakeRemote({'street'});
      final geoapify = _FakeGeoapify();

      final result = await _repository(remote: remote, geoapify: geoapify)
          .locateApproximate(_query);

      expect(result?.precision, LocationPrecision.street);
      expect(geoapify.geocodeCalls, 1);
    });

    test('fora do ar: cai para a cascata do Nominatim', () async {
      final remote = _FakeRemote({'freeText'});
      final geoapify = _FakeGeoapify(fails: true);

      final result = await _repository(remote: remote, geoapify: geoapify)
          .locateApproximate(_query);

      expect(result?.precision, LocationPrecision.exact);
      expect(remote.calls, isNotEmpty);
    });

    // O plano gratuito não cobra excedente, ele para de responder. Sair antes
    // do limite mantém o app funcionando pelo plano B em vez de o usuário
    // descobrir a cota através de um erro.
    test('cota esgotada: nem tenta o Geoapify', () async {
      final remote = _FakeRemote({'freeText'});
      final geoapify = _FakeGeoapify(answer: exact);

      final result = await _repository(
        remote: remote,
        geoapify: geoapify,
        quota: _quota(budget: 0),
      ).locateApproximate(_query);

      expect(geoapify.geocodeCalls, 0);
      expect(result?.precision, LocationPrecision.exact);
      expect(remote.calls, isNotEmpty, reason: 'resolvido pelo plano B');
    });

    test('a chamada bem-sucedida desconta da cota do dia', () async {
      final quota = _quota(budget: 100);
      await _repository(
        remote: _FakeRemote({}),
        geoapify: _FakeGeoapify(answer: exact),
        quota: quota,
      ).locateApproximate(_query);

      expect(quota.spentToday, 1);
    });

    test('o resultado do Geoapify entra no cache com o provedor', () async {
      final cache = _FakeCache();
      await _repository(
        remote: _FakeRemote({}),
        geoapify: _FakeGeoapify(answer: exact),
        cache: cache,
      ).locateApproximate(_query);

      expect(cache.providers.values, ['geoapify']);
    });
  });

  group('suggest', () {
    final suggestion = AddressSuggestion(
      label: 'Rua Carlos Ollig, 20',
      detail: 'Pinheiros · Apiaí · SP',
      query: _query,
      point: _found,
      precision: LocationPrecision.exact,
    );

    test('devolve as sugestões do Geoapify', () async {
      final geoapify = _FakeGeoapify(suggestions: [suggestion]);
      final result = await _repository(remote: _FakeRemote({}), geoapify: geoapify)
          .suggest('Rua Carlos Ollig');

      expect(result, [suggestion]);
      expect(geoapify.autocompleteCalls, 1);
    });

    // Duas ou três letras devolvem o Brasil inteiro. A sugestão não serviria e
    // a cota iria embora do mesmo jeito.
    test('texto curto demais não vira chamada', () async {
      final geoapify = _FakeGeoapify(suggestions: [suggestion]);
      final result = await _repository(remote: _FakeRemote({}), geoapify: geoapify)
          .suggest('Rua');

      expect(result, isEmpty);
      expect(geoapify.autocompleteCalls, 0);
    });

    test('o mesmo texto de novo sai da memória', () async {
      final geoapify = _FakeGeoapify(suggestions: [suggestion]);
      final repository =
          _repository(remote: _FakeRemote({}), geoapify: geoapify);

      await repository.suggest('Rua Carlos Ollig');
      await repository.suggest('rua  carlos ollig');

      expect(geoapify.autocompleteCalls, 1, reason: 'a segunda veio do memo');
    });

    // O Nominatim proíbe autocomplete na política de uso, e ser bloqueado lá
    // derrubaria também o geocoding, que importa mais.
    test('sem Geoapify não há sugestão nenhuma', () async {
      final remote = _FakeRemote({'freeText'});
      final result = await _repository(
        remote: remote,
        geoapify: _FakeGeoapify(configured: false),
      ).suggest('Rua Carlos Ollig');

      expect(result, isEmpty);
      expect(remote.calls, isEmpty);
    });

    test('offline não tenta sugerir', () async {
      final geoapify = _FakeGeoapify(suggestions: [suggestion]);
      final result = await _repository(
        remote: _FakeRemote({}),
        geoapify: geoapify,
        connected: false,
      ).suggest('Rua Carlos Ollig');

      expect(result, isEmpty);
      expect(geoapify.autocompleteCalls, 0);
    });

    // A sugestão já veio com coordenada. Localizar esse endereço depois não
    // pode gastar outra chamada para descobrir o que já se sabe.
    test('a sugestão escolhida dispensa a consulta seguinte', () async {
      final cache = _FakeCache();
      final geoapify = _FakeGeoapify(suggestions: [suggestion]);
      final repository =
          _repository(remote: _FakeRemote({}), geoapify: geoapify, cache: cache);

      await repository.rememberSuggestion(suggestion);
      final located = await repository.locateApproximate(_query);

      expect(located?.point, _found);
      expect(geoapify.geocodeCalls, 0);
    });
  });

  group('LocationPrecision', () {
    test('quanto mais grosseira a precisão, mais aberto o zoom', () async {
      expect(
        LocationPrecision.exact.zoom,
        greaterThan(LocationPrecision.neighborhood.zoom),
      );
      expect(
        LocationPrecision.neighborhood.zoom,
        greaterThan(LocationPrecision.city.zoom),
      );
    });

    test('só o exato dispensa ajuste', () {
      expect(LocationPrecision.exact.needsAdjustment, isFalse);
      expect(LocationPrecision.street.needsAdjustment, isTrue);
      expect(LocationPrecision.city.needsAdjustment, isTrue);
    });
  });
}
