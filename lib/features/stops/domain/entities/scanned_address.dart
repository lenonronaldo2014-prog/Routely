import 'package:equatable/equatable.dart';

/// Quanto dá para confiar no que foi lido da etiqueta.
enum ScanConfidence {
  /// Rótulos explícitos encontrados ("Endereço:", "CEP:"). É o caso das
  /// etiquetas de marketplace e o que dá para preencher quase inteiro.
  labelled,

  /// Sem rótulos, mas o CEP e/ou um logradouro plausível foram identificados
  /// por formato. Preenche o que deu e pede revisão.
  inferred,

  /// Não deu para identificar endereço nenhum.
  none,
}

/// O que foi extraído de uma foto de etiqueta.
///
/// Nunca é salvo direto: vira sugestão numa tela de confirmação. OCR errado
/// que vira entrega errada destrói a confiança no app, e um toque de conferir
/// custa um segundo.
class ScannedAddress extends Equatable {
  final String? street;
  final String? number;
  final String? complement;
  final String? neighborhood;
  final String? city;
  final String? state;
  final String? cep;

  /// Nome que aparecia na etiqueta — vira apelido da entrega, o que ajuda o
  /// entregador a reconhecer o pacote na hora.
  final String? recipient;

  final ScanConfidence confidence;

  /// Texto cru que o OCR devolveu, guardado para a tela de conferência poder
  /// mostrar o que foi lido quando o parser não achou nada.
  final String rawText;

  const ScannedAddress({
    this.street,
    this.number,
    this.complement,
    this.neighborhood,
    this.city,
    this.state,
    this.cep,
    this.recipient,
    required this.confidence,
    required this.rawText,
  });

  factory ScannedAddress.empty(String rawText) =>
      ScannedAddress(confidence: ScanConfidence.none, rawText: rawText);

  bool get hasAnything =>
      (street?.isNotEmpty ?? false) ||
      (cep?.isNotEmpty ?? false) ||
      (city?.isNotEmpty ?? false);

  /// Com CEP e número dá para montar o endereço inteiro pela base de CEP —
  /// que é exatamente o caminho mais confiável de leitura.
  bool get hasCepAndNumber =>
      (cep?.isNotEmpty ?? false) && (number?.isNotEmpty ?? false);

  @override
  List<Object?> get props => [
        street,
        number,
        complement,
        neighborhood,
        city,
        state,
        cep,
        recipient,
        confidence,
        rawText,
      ];
}
