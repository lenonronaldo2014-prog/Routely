import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/address_query.dart';
import '../../domain/entities/delivery_stop.dart';
import '../../domain/repositories/address_repository.dart';
import '../../domain/repositories/stops_repository.dart';
import '../datasources/history_local_data_source.dart';
import '../datasources/stops_local_data_source.dart';
import '../models/stop_model.dart';

/// Offline-first: o SQLite é a fonte da verdade. A rede só enriquece o que já
/// está gravado — nunca é pré-requisito para o usuário cadastrar uma entrega.
class StopsRepositoryImpl implements StopsRepository {
  final StopsLocalDataSource localDataSource;
  final AddressRepository addressRepository;
  final HistoryLocalDataSource historyDataSource;

  StopsRepositoryImpl({
    required this.localDataSource,
    required this.addressRepository,
    required this.historyDataSource,
  });

  @override
  Future<Either<Failure, List<DeliveryStop>>> getStops() async {
    try {
      final stops = await localDataSource.getStops();
      return Right(stops);
    } on CacheException {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, DeliveryStop>> saveStop(DeliveryStop stop) async {
    var resolved = stop;

    // O geocoding acontece aqui, uma vez, no cadastro — e a coordenada fica
    // gravada. O cálculo de rota depois lê o que está no banco e nunca
    // geocodifica de novo: seria pagar toda vez que o entregador recalcula o
    // roteiro, que é várias vezes por dia, pelo mesmo endereço.
    //
    // Quando não dá para localizar, a parada é salva mesmo assim, marcada como
    // "sem localização". Ela fica de fora da rota até o usuário marcar o ponto
    // no mapa — perder o cadastro seria pior.
    if (!stop.isRoutable) {
      final located = await addressRepository.locateApproximate(
        stop.addressQuery,
      );
      if (_isPreciseEnough(located)) {
        resolved = stop.copyWith(coordinate: located!.point);
      }
    }

    try {
      await localDataSource.upsertStop(StopModel.fromEntity(resolved));
      return Right(resolved);
    } on CacheException {
      return Left(CacheFailure());
    }
  }

  /// Até bairro serve para ordenar a rota; o centro da cidade não.
  ///
  /// Um erro de alguns quarteirões muda pouco a ordem das paradas, que é o que
  /// o app decide. Já o centroide da cidade colocaria paradas de bairros
  /// opostos no mesmo ponto e produziria um roteiro que parece calculado e
  /// está errado — pior que assumir que não achou e pedir o ponto no mapa.
  bool _isPreciseEnough(ApproximateLocation? located) =>
      located != null &&
      located.point.isValid &&
      located.precision != LocationPrecision.city;

  @override
  Future<Either<Failure, void>> deleteStop(String id) async {
    try {
      await localDataSource.deleteStop(id);
      return const Right(null);
    } on CacheException {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, DeliveryStop>> setStatus(
    DeliveryStop stop,
    StopStatus status,
  ) async {
    final updated = stop.copyWith(
      status: status,
      completedAt: status == StopStatus.pending ? null : DateTime.now(),
      clearCompletedAt: status == StopStatus.pending,
    );

    try {
      await localDataSource.upsertStop(StopModel.fromEntity(updated));
      return Right(updated);
    } on CacheException {
      return Left(CacheFailure());
    }
  }

  /// "Limpar concluídas" **arquiva**, não apaga.
  ///
  /// Antes isso deletava e o entregador perdia o registro do próprio dia de
  /// trabalho — quantas entregas fez, quanto rodou. Agora sai da lista ativa e
  /// vai para o histórico.
  @override
  Future<Either<Failure, int>> clearCompleted() async {
    try {
      final archived = await historyDataSource.archiveCompleted();
      return Right(archived);
    } on CacheException {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, List<DeliveryStop>>>
      resolvePendingCoordinates() async {
    try {
      final stops = await localDataSource.getStops();
      final unresolved =
          stops.where((s) => !s.isRoutable && s.isPending).toList();

      for (final stop in unresolved) {
        final located =
            await addressRepository.locateApproximate(stop.addressQuery);

        // Sem rede ou endereço não encontrado: deixa como está e tenta de novo
        // na próxima vez. Não faz sentido insistir agora.
        if (!_isPreciseEnough(located)) continue;

        await localDataSource.upsertStop(
          StopModel.fromEntity(stop.copyWith(coordinate: located!.point)),
        );
      }

      return Right(await localDataSource.getStops());
    } on CacheException {
      return Left(CacheFailure());
    }
  }
}
