import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/app_config.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/geo/geo_point.dart';
import '../../domain/entities/address_query.dart';
import '../../domain/entities/address_suggestion.dart';

/// Geocoding pelo Geoapify.
///
/// Substituiu o Nominatim como fonte principal porque o OpenStreetMap não
/// cobre cidade pequena no Brasil. Medido contra o serviço real, o endereço
/// "Rua Carlos Ollig, 20, Apiaí/SP" não existia lá em nenhuma forma de
/// consulta — nem a rua, nem o CEP, nem o bairro — e o app só conseguia abrir
/// o mapa no centro da cidade.
///
/// O Nominatim continua no projeto como plano B, para quando a cota diária
/// acabar. Ficar sem geocoding é pior que geocodificar mal.
abstract class GeoapifyRemoteDataSource {
  /// Se há chave (ou proxy) para consultar.
  ///
  /// Quem decide usar o plano B precisa saber disso, e a informação mora aqui
  /// — é este objeto que guarda a chave. Deixar o repositório ler a
  /// configuração global o tornaria impossível de testar sem compilar com
  /// chave.
  bool get isConfigured;

  /// Endereço em campos separados -> coordenada e o quanto ela é precisa.
  ///
  /// Null quando o serviço não achou nada aproveitável. "Aproveitável" exclui
  /// acerto no nível de estado ou país: o centro de São Paulo-estado não ajuda
  /// ninguém a entregar nada, e mostrar isso como resultado seria pior que
  /// admitir que não achou.
  Future<ApproximateLocation?> geocode(AddressQuery query);

  /// Sugestões para o que está sendo digitado, já com coordenada.
  ///
  /// [bias] aproxima os resultados de onde o usuário está. Sem isso, digitar
  /// "Rua São João" devolve as de todo o Brasil, e a certa dificilmente estaria
  /// entre as cinco primeiras.
  Future<List<AddressSuggestion>> autocomplete(String text, {GeoPoint? bias});
}

class GeoapifyRemoteDataSourceImpl implements GeoapifyRemoteDataSource {
  static const _direct = 'https://api.geoapify.com/v1/geocode';
  static const _timeout = Duration(seconds: 10);

  /// Poucas opções de propósito: lista longa em tela de celular obriga a rolar
  /// no meio da digitação, e o endereço certo quase sempre está no topo.
  static const _suggestionLimit = 5;

  final http.Client client;
  final String apiKey;

  /// Quando preenchido, as consultas vão para cá em vez de irem ao Geoapify, e
  /// nenhuma chave sai do aparelho — quem guarda a chave é o servidor.
  final String proxyBase;

  GeoapifyRemoteDataSourceImpl({
    required this.client,
    String? apiKey,
    String? proxyBase,
  })  : apiKey = apiKey ?? AppConfig.geoapifyKey,
        proxyBase = proxyBase ?? AppConfig.geoapifyProxy;

  bool get _viaProxy => proxyBase.isNotEmpty;

  String get _base => _viaProxy ? proxyBase : _direct;

  @override
  bool get isConfigured => _viaProxy || apiKey.isNotEmpty;

  @override
  Future<ApproximateLocation?> geocode(AddressQuery query) async {
    final cep = query.normalizedCep;

    final params = <String, String>{
      if ((query.number ?? '').trim().isNotEmpty)
        'housenumber': query.number!.trim(),
      if (query.hasStreet) 'street': query.street!.trim(),
      'postcode': ?cep,
      if (query.hasCity) 'city': query.city!.trim(),
      if ((query.state ?? '').trim().isNotEmpty) 'state': query.state!.trim(),
      'country': 'Brazil',
      'limit': '1',
    };

    final results = await _get('search', params);
    if (results.isEmpty) return null;

    final place = _parse(results.first);
    return place == null
        ? null
        : ApproximateLocation(point: place.point, precision: place.precision);
  }

  @override
  Future<List<AddressSuggestion>> autocomplete(
    String text, {
    GeoPoint? bias,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];

    final proximity =
        bias == null ? null : 'proximity:${bias.longitude},${bias.latitude}';

    final results = await _get('autocomplete', {
      'text': trimmed,
      'filter': 'countrycode:br',
      'bias': ?proximity,
      'limit': '$_suggestionLimit',
    });

    return results
        .map(_parse)
        .whereType<AddressSuggestion>()
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _get(
    String endpoint,
    Map<String, String> params,
  ) async {
    if (!_viaProxy && apiKey.isEmpty) {
      throw GeocodingException('Geoapify sem chave configurada.');
    }

    final uri = Uri.parse('$_base/$endpoint').replace(queryParameters: {
      ...params,
      'lang': 'pt',
      'format': 'json',
      if (!_viaProxy) 'apiKey': apiKey,
    });

    final response = await client.get(uri).timeout(_timeout);

    if (response.statusCode != 200) {
      throw ServerException(statusCode: response.statusCode);
    }

    final body = json.decode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) return const [];

    final results = body['results'];
    if (results is! List) return const [];

    return results.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  /// Null quando o resultado não tem coordenada utilizável ou é grosseiro
  /// demais para servir de destino de entrega.
  AddressSuggestion? _parse(Map<String, dynamic> result) {
    final lat = _toDouble(result['lat']);
    final lon = _toDouble(result['lon']);
    if (lat == null || lon == null) return null;

    final point = GeoPoint(latitude: lat, longitude: lon);
    if (!point.isValid) return null;

    final precision = _precisionOf(result['result_type'] as String?);
    if (precision == null) return null;

    final street = _text(result['street']);
    final number = _text(result['housenumber']);
    final city = _text(result['city']);
    final state = _ufOf(result);
    final cep = _text(result['postcode']);

    // `suburb` é o bairro. `district` às vezes traz o bairro e às vezes repete
    // o nome da cidade — visto em Apiaí/SP, que voltou `district: "Apiaí"`.
    // Copiar isso para o campo bairro encheria o formulário com a cidade
    // escrita duas vezes.
    final district = _text(result['district']);
    final neighborhood =
        _text(result['suburb']) ?? (district == city ? null : district);

    final label = [?street, ?number].join(', ');
    final detail = [?neighborhood, ?city, ?state, ?cep].join(' · ');

    return AddressSuggestion(
      // Sem rua no resultado (um bairro ou uma cidade), o texto formatado do
      // próprio serviço é a melhor descrição disponível.
      label: label.isNotEmpty
          ? label
          : (_text(result['formatted']) ?? city ?? 'Endereço'),
      detail: detail,
      query: AddressQuery(
        cep: cep,
        street: street,
        number: number,
        neighborhood: neighborhood,
        city: city,
        state: state,
      ),
      point: point,
      precision: precision,
    );
  }

  /// Traduz o tipo do resultado para o quanto dá para confiar nele.
  ///
  /// `state` e `country` ficam de fora: acertar o estado não é chegar perto de
  /// uma porta, e apresentar isso como localização enganaria o usuário.
  static LocationPrecision? _precisionOf(String? resultType) =>
      switch (resultType) {
        'building' || 'amenity' => LocationPrecision.exact,
        'street' => LocationPrecision.street,
        'postcode' => LocationPrecision.postalCode,
        'suburb' || 'district' || 'neighbourhood' =>
          LocationPrecision.neighborhood,
        'city' || 'county' || 'municipality' => LocationPrecision.city,
        _ => null,
      };

  /// A UF, procurada em mais de um campo porque o Geoapify não é consistente
  /// no Brasil.
  ///
  /// No caso comum vem `state_code: "SP"`. Mas resultados vindos do
  /// OpenAddresses trazem `state: "Sudeste"` — a **região** — e escondem a UF
  /// em `county_code`. Verificado com "Rua Carlos Olig, 20, Apiaí": sem este
  /// tratamento o formulário receberia "Sudeste" no campo UF.
  ///
  /// Só aceita duas letras. Qualquer outra coisa é nome de estado ou de
  /// região, e deixar o campo vazio é melhor que preenchê-lo errado.
  static String? _ufOf(Map<String, dynamic> result) {
    for (final key in ['state_code', 'county_code', 'state']) {
      final value = _text(result[key]);
      if (value != null && RegExp(r'^[A-Za-z]{2}$').hasMatch(value)) {
        return value.toUpperCase();
      }
    }
    return null;
  }

  static double? _toDouble(Object? value) => switch (value) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      };

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
