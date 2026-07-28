import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/scanned_address.dart';
import '../../domain/repositories/label_scanner_repository.dart';
import '../../domain/services/label_parser.dart';
import '../datasources/label_scanner_data_source.dart';

class LabelScannerRepositoryImpl implements LabelScannerRepository {
  final LabelScannerDataSource dataSource;
  final LabelParser parser;

  LabelScannerRepositoryImpl({
    required this.dataSource,
    required this.parser,
  });

  @override
  Future<Either<Failure, ScannedAddress>> scanLabel(String imagePath) async {
    try {
      final text = await dataSource.recognizeText(imagePath);
      final scanned = parser.parse(text);

      if (!scanned.hasAnything) {
        return Left(ScanFailure(
          'Não consegui achar um endereço nessa foto. '
          'Tente enquadrar só a etiqueta, com boa luz.',
        ));
      }

      return Right(scanned);
    } on ScanException {
      return Left(ScanFailure('Não consegui ler a foto. Tente de novo.'));
    } catch (_) {
      return Left(ScanFailure('Erro inesperado ao ler a etiqueta.'));
    }
  }
}
