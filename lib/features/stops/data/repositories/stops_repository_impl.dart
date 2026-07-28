import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
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

    // Ordem de resolução da coordenada, do mais barato para o mais caro:
    //
    // 1. base de CEP local — instantânea, offline, sem custo por usuário. É o
    //    que mantém o app viável de operar de graça em escala;
    // 2. geocoding online — só quando a base não cobre o CEP;
    // 3. nada — a parada é salva mesmo assim, marcada como "sem localização",
    //    e o usuário resolve no mapa quando quiser.
    if (!stop.isRoutable && stop.cep != null) {
      final local = await addressRepository.coordinateFromDirectory(stop.cep!);
      if (local != null) resolved = stop.copyWith(coordinate: local);
    }

    if (!resolved.isRoutable) {
      final geocodeResult = await addressRepository.geocode(stop.fullAddress);
      resolved = geocodeResult.fold(
        (_) => resolved,
        (point) => resolved.copyWith(coordinate: point),
      );
    }

    try {
      await localDataSource.upsertStop(StopModel.fromEntity(resolved));
      return Right(resolved);
    } on CacheException {
      return Left(CacheFailure());
    }
  }

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
        final result = await addressRepository.geocode(stop.fullAddress);
        await result.fold(
          // Sem rede ou endereço não encontrado: deixa como está e tenta de
          // novo na próxima vez. Não faz sentido insistir agora.
          (_) async {},
          (point) async {
            await localDataSource.upsertStop(
              StopModel.fromEntity(stop.copyWith(coordinate: point)),
            );
          },
        );
      }

      return Right(await localDataSource.getStops());
    } on CacheException {
      return Left(CacheFailure());
    }
  }
}
