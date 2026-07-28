import 'package:equatable/equatable.dart';

/// Uma base de CEP de um estado, já instalada no aparelho.
class CepPack extends Equatable {
  final String state;
  final int entryCount;
  final DateTime importedAt;

  /// Identifica a versão do arquivo importado, para saber se vale reimportar.
  final String? sourceVersion;

  const CepPack({
    required this.state,
    required this.entryCount,
    required this.importedAt,
    this.sourceVersion,
  });

  @override
  List<Object?> get props => [state, entryCount, importedAt, sourceVersion];
}

/// Progresso da importação. Uma base estadual tem centenas de milhares de
/// linhas — sem feedback o usuário acha que travou.
class CepImportProgress extends Equatable {
  final int processed;

  /// Nulo quando o total ainda não é conhecido (leitura em fluxo).
  final int? total;

  const CepImportProgress({required this.processed, this.total});

  double? get fraction {
    if (total == null || total == 0) return null;
    return (processed / total!).clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => [processed, total];
}
