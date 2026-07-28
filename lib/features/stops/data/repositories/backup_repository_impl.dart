import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/repositories/backup_repository.dart';
import '../datasources/backup_data_source.dart';

class BackupRepositoryImpl implements BackupRepository {
  final BackupDataSource dataSource;

  BackupRepositoryImpl({required this.dataSource});

  @override
  Future<Either<Failure, File>> exportToFile() async {
    try {
      final content = await dataSource.export();

      // Nome com a data para o usuário reconhecer o arquivo depois — ele vai
      // guardar isso no WhatsApp ou no Drive junto de outras coisas.
      final now = DateTime.now();
      final stamp = '${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final directory = await getTemporaryDirectory();
      final file = File(p.join(directory.path, 'routely-backup-$stamp.json'));
      await file.writeAsString(content);

      return Right(file);
    } on CacheException {
      return Left(CacheFailure());
    } catch (_) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, BackupSummary>> importFromFile(File file) async {
    try {
      final content = await file.readAsString();
      return Right(await dataSource.import(content));
    } on BackupFormatException catch (e) {
      return Left(GeocodingFailure(e.message));
    } on CacheException {
      return Left(CacheFailure());
    } on FileSystemException {
      return Left(GeocodingFailure('Não foi possível ler o arquivo.'));
    } catch (_) {
      return Left(GeocodingFailure('Arquivo inválido.'));
    }
  }
}
