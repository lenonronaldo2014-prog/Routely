import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/error/exceptions.dart';
import '../../../../core/geo/geo_point.dart';
import '../../domain/entities/address_lookup.dart';

abstract class AddressRemoteDataSource {
  /// CEP (só dígitos) -> logradouro, bairro, cidade, UF.
  Future<AddressLookup> lookupCep(String cep);

  /// Endereço em texto -> coordenada.
  Future<GeoPoint> geocode(String fullAddress);

  /// Busca por campos separados.
  ///
  /// O Nominatim acerta bem mais assim do que com tudo colado numa frase:
  /// informar "esta parte é rua, esta é cidade" evita que ele interprete o
  /// nome do bairro como nome de rua, por exemplo. É o que permite achar a rua
  /// quando o número não existe no mapa.
  Future<GeoPoint> geocodeStructured({
    String? street,
    String? city,
    String? state,
    String? postalCode,
  });
}

class AddressRemoteDataSourceImpl implements AddressRemoteDataSource {
  /// Nominatim exige User-Agent identificando a aplicação. Requisição sem isso
  /// é bloqueada.
  static const _userAgent = 'Routely/1.0 (contato@routely.app)';

  static const _viaCepBase = 'https://viacep.com.br/ws';
  static const _nominatimBase = 'https://nominatim.openstreetmap.org/search';

  static const _timeout = Duration(seconds: 10);

  final http.Client client;

  AddressRemoteDataSourceImpl({required this.client});

  @override
  Future<AddressLookup> lookupCep(String cep) async {
    final response = await client
        .get(Uri.parse('$_viaCepBase/$cep/json/'))
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw ServerException(statusCode: response.statusCode);
    }

    final body = json.decode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw GeocodingException('Resposta inesperada do serviço de CEP.');
    }

    // ViaCEP devolve 200 com {"erro": true} para CEP inexistente.
    if (body['erro'] != null) {
      throw GeocodingException('CEP não encontrado.');
    }

    return AddressLookup(
      cep: (body['cep'] as String?) ?? cep,
      street: (body['logradouro'] as String?) ?? '',
      neighborhood: (body['bairro'] as String?) ?? '',
      city: (body['localidade'] as String?) ?? '',
      state: (body['uf'] as String?) ?? '',
      source: AddressSource.network,
    );
  }

  @override
  Future<GeoPoint> geocode(String fullAddress) {
    return _search({'q': fullAddress});
  }

  @override
  Future<GeoPoint> geocodeStructured({
    String? street,
    String? city,
    String? state,
    String? postalCode,
  }) {
    final params = <String, String>{
      if (street != null && street.trim().isNotEmpty) 'street': street.trim(),
      if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
      if (state != null && state.trim().isNotEmpty) 'state': state.trim(),
      if (postalCode != null && postalCode.trim().isNotEmpty)
        'postalcode': postalCode.trim(),
    };

    if (params.isEmpty) {
      throw GeocodingException('Nada para buscar.');
    }

    return _search(params);
  }

  Future<GeoPoint> _search(Map<String, String> query) async {
    final uri = Uri.parse(_nominatimBase).replace(queryParameters: {
      ...query,
      'format': 'jsonv2',
      'limit': '1',
      'countrycodes': 'br',
    });

    final response = await client.get(
      uri,
      headers: {'User-Agent': _userAgent, 'Accept-Language': 'pt-BR'},
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw ServerException(statusCode: response.statusCode);
    }

    final body = json.decode(utf8.decode(response.bodyBytes));
    if (body is! List || body.isEmpty) {
      throw GeocodingException('Endereço não localizado no mapa.');
    }

    final first = body.first as Map<String, dynamic>;
    final lat = double.tryParse(first['lat'] as String? ?? '');
    final lon = double.tryParse(first['lon'] as String? ?? '');

    if (lat == null || lon == null) {
      throw GeocodingException('Coordenada inválida para este endereço.');
    }

    return GeoPoint(latitude: lat, longitude: lon);
  }
}
