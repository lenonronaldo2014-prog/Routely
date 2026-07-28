import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/scanned_address.dart';

abstract class LabelScannerRepository {
  /// Lê a etiqueta fotografada e devolve o que conseguiu identificar.
  ///
  /// Só falha quando não deu para ler **nada**. Leitura parcial volta como
  /// sucesso com campos vazios — quem decide se está bom é o usuário, na tela
  /// de conferência.
  Future<Either<Failure, ScannedAddress>> scanLabel(String imagePath);
}
