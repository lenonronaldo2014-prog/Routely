import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/geo/geo_point.dart';
import '../entities/address_lookup.dart';
import '../entities/address_query.dart';

abstract class AddressRepository {
  /// Consulta CEP. Tenta o cache local primeiro — o que também faz funcionar
  /// offline para CEPs já vistos.
  Future<Either<Failure, AddressLookup>> lookupCep(String cep);

  /// Converte endereço em texto para coordenada.
  Future<Either<Failure, GeoPoint>> geocode(String fullAddress);

  /// Acha o ponto mais próximo possível do endereço, afrouxando a busca até
  /// conseguir algo.
  ///
  /// Um endereço que o mapa não conhece não deveria terminar em "não achei":
  /// se a rua existe, vale abrir na rua; se só o bairro existe, vale abrir no
  /// bairro. Chegar perto e deixar o usuário ajustar é muito melhor do que
  /// jogá-lo na própria localização, que pode estar do outro lado da cidade.
  ///
  /// A precisão alcançada volta junto, para a tela poder ser honesta sobre o
  /// quanto ainda falta ajustar. Null quando nem a cidade foi encontrada.
  Future<ApproximateLocation?> locateApproximate(AddressQuery query);

  /// Coordenada vinda da base local, pelo CEP. Null quando a base não está
  /// instalada ou não tem o ponto.
  ///
  /// É o caminho mais barato que existe: sem rede, sem custo por usuário e
  /// instantâneo. O centroide do CEP erra uns 100-200m em área urbana, o que
  /// não muda a ordem das paradas — que é o que o app decide.
  Future<GeoPoint?> coordinateFromDirectory(String cep);
}
