import 'dart:io';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../data/datasources/backup_data_source.dart';

abstract class BackupRepository {
  /// Gera o arquivo de backup e devolve o caminho, pronto para compartilhar.
  Future<Either<Failure, File>> exportToFile();

  Future<Either<Failure, BackupSummary>> importFromFile(File file);
}
