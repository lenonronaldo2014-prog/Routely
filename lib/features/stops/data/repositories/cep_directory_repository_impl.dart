import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/cep_pack.dart';
import '../../domain/repositories/cep_directory_repository.dart';
import '../datasources/cep_directory_local_data_source.dart';

class CepDirectoryRepositoryImpl implements CepDirectoryRepository {
  final CepDirectoryLocalDataSource localDataSource;

  CepDirectoryRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, List<CepPack>>> installedPacks() async {
    try {
      return Right(await localDataSource.installedPacks());
    } on CacheException {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, int>> importFromFile({
    required String state,
    required File file,
    String? sourceVersion,
    void Function(CepImportProgress progress)? onProgress,
  }) async {
    try {
      // Lê em fluxo, linha a linha. Uma base estadual tem centenas de milhares
      // de linhas — carregar o arquivo inteiro na memória estouraria em
      // aparelho modesto, que é justamente o público do app.
      final lines = file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      final imported = await localDataSource.importState(
        state: state,
        lines: lines,
        sourceVersion: sourceVersion,
        onProgress: onProgress,
      );

      if (imported == 0) {
        return Left(GeocodingFailure(
          'Nenhuma linha válida para $state neste arquivo. '
          'Confira o formato: cep;logradouro;bairro;cidade;uf',
        ));
      }

      return Right(imported);
    } on CacheException {
      return Left(CacheFailure());
    } on FileSystemException {
      return Left(GeocodingFailure('Não foi possível ler o arquivo.'));
    } catch (_) {
      return Left(GeocodingFailure('Arquivo inválido ou corrompido.'));
    }
  }

  @override
  Future<Either<Failure, void>> removePack(String state) async {
    try {
      await localDataSource.removeState(state);
      return const Right(null);
    } on CacheException {
      return Left(CacheFailure());
    }
  }
}
