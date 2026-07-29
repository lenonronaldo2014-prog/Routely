import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:routely/core/error/exceptions.dart';
import 'package:routely/features/stops/data/datasources/geoapify_remote_data_source.dart';
import 'package:routely/features/stops/domain/entities/address_query.dart';

/// Cliente que devolve sempre a mesma resposta e guarda a URL pedida.
class _CannedClient extends http.BaseClient {
  final String body;
  final int statusCode;
  Uri? lastUri;

  _CannedClient(this.body, {this.statusCode = 200});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUri = request.url;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
    );
  }
}

/// Resposta real do Geoapify para "Rua Carlos Olig, 20, Apiaí/SP", reduzida
/// aos campos que o app lê.
///
/// Este resultado vem do OpenAddresses, que mapeia a divisão administrativa
/// brasileira errado: põe a **região** em `state`, a UF em `county_code`, e
/// repete a cidade em `district`. É o caso que quebra um parser ingênuo.
const _openAddressesBody = '''
{"results":[{
  "country_code":"br",
  "housenumber":"20",
  "street":"Rua Carlos Olig",
  "country":"Brasil",
  "county":"São Paulo",
  "postcode":"18320-000",
  "state":"Sudeste",
  "district":"Apiaí",
  "city":"Apiaí",
  "county_code":"SP",
  "lon":-48.843482,
  "lat":-24.493582,
  "result_type":"building",
  "formatted":"Rua Carlos Olig 20, Apiaí - Sudeste, 18320-000, Brasil"
}]}
''';

/// Resposta real para "Avenida Paulista 1578" — o formato comum, com
/// `state_code` presente e `suburb` trazendo o bairro de verdade.
const _commonBody = '''
{"results":[{
  "country_code":"br",
  "housenumber":"1578",
  "street":"Avenida Paulista",
  "suburb":"Bela Vista",
  "city":"São Paulo",
  "state":"São Paulo",
  "state_code":"SP",
  "postcode":"01310-200",
  "lon":-46.6558,
  "lat":-23.5614,
  "result_type":"building",
  "formatted":"Avenida Paulista 1578, São Paulo"
}]}
''';

GeoapifyRemoteDataSourceImpl _source(_CannedClient client) =>
    GeoapifyRemoteDataSourceImpl(client: client, apiKey: 'chave-de-teste');

void main() {
  group('leitura da resposta', () {
    test('acha o prédio exato onde o Nominatim não achava nada', () async {
      final client = _CannedClient(_openAddressesBody);
      final result = await _source(client).geocode(const AddressQuery(
        cep: '18320620',
        street: 'Rua Carlos Ollig',
        number: '20',
        city: 'Apiaí',
        state: 'SP',
      ));

      expect(result?.precision, LocationPrecision.exact);
      expect(result?.point.latitude, closeTo(-24.493582, 0.000001));
      expect(result?.point.longitude, closeTo(-48.843482, 0.000001));
    });

    test('a UF sai de county_code quando state traz a região', () async {
      final client = _CannedClient(_openAddressesBody);
      final suggestions = await _source(client).autocomplete('Rua Carlos Olig');

      expect(suggestions.single.query.state, 'SP');
    });

    // `district` repetindo o nome da cidade encheria o campo bairro com a
    // cidade escrita duas vezes.
    test('district igual à cidade não vira bairro', () async {
      final client = _CannedClient(_openAddressesBody);
      final suggestions = await _source(client).autocomplete('Rua Carlos Olig');

      expect(suggestions.single.query.neighborhood, isNull);
      expect(suggestions.single.query.city, 'Apiaí');
    });

    test('no formato comum lê state_code e suburb', () async {
      final client = _CannedClient(_commonBody);
      final suggestions = await _source(client).autocomplete('Avenida Paulista');

      final query = suggestions.single.query;
      expect(query.state, 'SP');
      expect(query.neighborhood, 'Bela Vista');
      expect(query.street, 'Avenida Paulista');
      expect(query.number, '1578');
      expect(suggestions.single.label, 'Avenida Paulista, 1578');
    });

    // Acertar o estado não é chegar perto de uma porta. Mostrar isso como
    // localização faria o usuário confirmar um ponto a centenas de quilômetros.
    test('resultado no nível de estado é descartado', () async {
      final client = _CannedClient(
        '{"results":[{"lat":-23.5,"lon":-46.6,"result_type":"state"}]}',
      );

      expect(await _source(client).geocode(const AddressQuery(city: 'X')), isNull);
      expect(await _source(client).autocomplete('São Paulo'), isEmpty);
    });

    // O 429 é o que o Geoapify responde quando a cota acabou. Ele precisa
    // virar exceção para o repositório cair no plano B; engolir isso deixaria
    // o app achando que o endereço não existe.
    test('cota estourada no servidor vira exceção', () async {
      final client = _CannedClient('{"error":"quota"}', statusCode: 429);

      expect(
        () => _source(client).geocode(const AddressQuery(city: 'X')),
        throwsA(isA<ServerException>()),
      );
    });

    test('resposta vazia não vira erro', () async {
      final client = _CannedClient('{"results":[]}');

      expect(await _source(client).geocode(const AddressQuery(city: 'X')), isNull);
      expect(await _source(client).autocomplete('nada disso'), isEmpty);
    });
  });

  group('montagem da consulta', () {
    test('manda os campos separados, não uma frase', () async {
      final client = _CannedClient(_commonBody);
      await _source(client).geocode(const AddressQuery(
        cep: '01310-200',
        street: 'Avenida Paulista',
        number: '1578',
        city: 'São Paulo',
        state: 'SP',
      ));

      final params = client.lastUri!.queryParameters;
      expect(params['housenumber'], '1578');
      expect(params['street'], 'Avenida Paulista');
      expect(params['postcode'], '01310200');
      expect(params['city'], 'São Paulo');
      expect(params['country'], 'Brazil');
    });

    test('o autocomplete se restringe ao Brasil', () async {
      final client = _CannedClient(_commonBody);
      await _source(client).autocomplete('Avenida Paulista');

      expect(client.lastUri!.queryParameters['filter'], 'countrycode:br');
    });

    // Sem chave nem proxy não há o que consultar, e o repositório precisa
    // saber disso para usar o plano B em vez de gastar uma requisição que
    // voltaria 401.
    test('sem chave se declara não configurado', () {
      final source = GeoapifyRemoteDataSourceImpl(
        client: _CannedClient('{}'),
        apiKey: '',
        proxyBase: '',
      );

      expect(source.isConfigured, isFalse);
    });

    // Com proxy a chave fica no servidor: nenhuma sai do aparelho.
    test('com proxy nenhuma chave é enviada', () async {
      final client = _CannedClient(_commonBody);
      final source = GeoapifyRemoteDataSourceImpl(
        client: client,
        apiKey: 'nao-deveria-sair',
        proxyBase: 'https://meu-servidor.exemplo/geocode',
      );

      await source.autocomplete('Avenida Paulista');

      expect(source.isConfigured, isTrue);
      expect(client.lastUri!.host, 'meu-servidor.exemplo');
      expect(client.lastUri!.queryParameters.containsKey('apiKey'), isFalse);
    });
  });
}
