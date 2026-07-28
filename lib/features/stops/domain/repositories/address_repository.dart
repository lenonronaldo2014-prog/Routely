import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../entities/address_lookup.dart';

abstract class AddressRepository {
  /// Consulta CEP. Tenta o cache local primeiro — o que também faz funcionar
  /// offline para CEPs já vistos.
  Future<Either<Failure, AddressLookup>> lookupCep(String cep);

  /// Converte endereço em texto para coordenada.
  Future<Either<Failure, GeoPoint>> geocode(String fullAddress);

  /// Coordenada vinda da base local, pelo CEP. Null quando a base não está
  /// instalada ou não tem o ponto.
  ///
  /// É o caminho mais barato que existe: sem rede, sem custo por usuário e
  /// instantâneo. O centroide do CEP erra uns 100-200m em área urbana, o que
  /// não muda a ordem das paradas — que é o que o app decide.
  Future<GeoPoint?> coordinateFromDirectory(String cep);
}
