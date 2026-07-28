import 'dart:io';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/cep_pack.dart';

abstract class CepDirectoryRepository {
  Future<Either<Failure, List<CepPack>>> installedPacks();

  /// Importa a base de um estado a partir de um arquivo escolhido pelo usuário.
  Future<Either<Failure, int>> importFromFile({
    required String state,
    required File file,
    String? sourceVersion,
    void Function(CepImportProgress progress)? onProgress,
  });

  Future<Either<Failure, void>> removePack(String state);
}
