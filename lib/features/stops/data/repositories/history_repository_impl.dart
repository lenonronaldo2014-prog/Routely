import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/delivery_record.dart';
import '../../domain/repositories/history_repository.dart';
import '../datasources/history_local_data_source.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryLocalDataSource localDataSource;

  HistoryRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, List<DeliveryDay>>> getHistory() async {
    try {
      final records = await localDataSource.getHistory();
      return Right(_groupByDay(records));
    } on CacheException {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> clearHistory() async {
    try {
      await localDataSource.clearHistory();
      return const Right(null);
    } on CacheException {
      return Left(CacheFailure());
    }
  }

  /// Agrupa por dia preservando a ordem que veio do banco (mais recente
  /// primeiro), porque é assim que o entregador procura: o dia de hoje no topo.
  List<DeliveryDay> _groupByDay(List<DeliveryRecord> records) {
    final byDay = <DateTime, List<DeliveryRecord>>{};

    for (final record in records) {
      byDay.putIfAbsent(record.day, () => []).add(record);
    }

    return byDay.entries
        .map((entry) => DeliveryDay(day: entry.key, records: entry.value))
        .toList()
      ..sort((a, b) => b.day.compareTo(a.day));
  }
}
