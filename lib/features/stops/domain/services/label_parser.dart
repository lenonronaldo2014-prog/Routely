import '../../../../core/util/brazil_states.dart';
import '../../../../core/util/cep_formatter.dart';
import '../../../../core/util/cep_range_resolver.dart';
import '../../../../core/util/text_normalizer.dart';
import '../entities/scanned_address.dart';

/// Extrai o endereço do texto que o OCR leu de uma etiqueta de encomenda.
///
/// A estratégia principal é **ancorar em rótulos**, não adivinhar por formato.
/// Etiqueta de marketplace escreve "Endereço:", "CEP:", "Cidade de destino:" —
/// e isso resolve o problema mais perigoso de graça: a etiqueta também traz o
/// endereço do **remetente**, mas sem rótulo nenhum. Procurar pelo rótulo
/// seleciona o destinatário sozinho.
///
/// Sem os rótulos ainda sobra um caminho por formato, mas com menos confiança.
class LabelParser {
  const LabelParser();

  /// Rótulos aceitos para cada campo, já sem acento — o OCR come cedilha com
  /// frequência.
  static const _streetLabels = ['endereco', 'destinatario', 'entregar em'];
  static const _cepLabels = ['cep'];
  static const _cityLabels = ['cidade de destino', 'cidade', 'municipio'];
  static const _complementLabels = ['complemento', 'compl'];

  /// Tipos de logradouro, para o caminho sem rótulo.
  static final _streetPrefix = RegExp(
    r'^(rua|r\.|av|av\.|avenida|alameda|al\.|travessa|tv\.|rodovia|rod\.|'
    r'estrada|est\.|praca|praça|largo|viela|servidao|quadra|conjunto)\b',
    caseSensitive: false,
  );

  /// Sequências longas de dígitos que NÃO são CEP: chave de acesso do DANFE
  /// (44), código de rastreio, número de venda. Sem esse filtro, um "achar 8
  /// dígitos" pegaria um pedaço da chave e mandaria o entregador para o outro
  /// lado do estado.
  static final _longDigitRun = RegExp(r'\d{9,}');

  ScannedAddress parse(String rawText) {
    if (rawText.trim().isEmpty) return ScannedAddress.empty(rawText);

    final lines = rawText
        .split('\n')
        .map(TextNormalizer.collapseSpaces)
        .where((line) => line.isNotEmpty)
        .toList();

    final labelled = _parseLabelled(lines, rawText);
    if (labelled != null) return labelled;

    return _parseByShape(lines, rawText);
  }

  // ---------------------------------------------------------------- rotulado

  ScannedAddress? _parseLabelled(List<String> lines, String rawText) {
    final streetLine = _valueFor(lines, _streetLabels);
    final cepLine = _valueFor(lines, _cepLabels);

    // Sem nenhum dos dois rótulos principais não é etiqueta estruturada.
    if (streetLine == null && cepLine == null) return null;

    final address = streetLine == null
        ? const _StreetParts()
        : _splitStreetLine(streetLine);

    final cityParts = _splitCityLine(_valueFor(lines, _cityLabels));

    return ScannedAddress(
      street: address.street,
      number: address.number,
      neighborhood: address.neighborhood,
      complement: _valueFor(lines, _complementLabels),
      city: cityParts.city,
      state: cityParts.state ??
          (cepLine == null ? null : CepRangeResolver.ufFor(cepLine)),
      cep: cepLine == null ? null : _extractCep(cepLine),
      recipient: _recipientBefore(lines, _streetLabels),
      confidence: ScanConfidence.labelled,
      rawText: rawText,
    );
  }

  /// Valor à direita do rótulo, na mesma linha. Quando a linha só tem o rótulo,
  /// pega a linha seguinte — algumas impressoras quebram ali.
  String? _valueFor(List<String> lines, List<String> labels) {
    for (var i = 0; i < lines.length; i++) {
      final normalized = TextNormalizer.normalize(lines[i]);

      for (final label in labels) {
        // Precisa começar com o rótulo seguido de ':' ou espaço, senão
        // "cidade" casaria no meio de qualquer frase.
        final match = RegExp('^$label\\s*:').firstMatch(normalized);
        if (match == null) continue;

        final value = lines[i].substring(match.end).trim();
        if (value.isNotEmpty) return value;

        if (i + 1 < lines.length) return lines[i + 1].trim();
      }
    }
    return null;
  }

  /// Nome logo acima da linha de endereço. Na etiqueta do Mercado Livre é o
  /// destinatário, e vira apelido da entrega.
  String? _recipientBefore(List<String> lines, List<String> labels) {
    for (var i = 0; i < lines.length; i++) {
      final normalized = TextNormalizer.normalize(lines[i]);
      final isStreetLine =
          labels.any((label) => normalized.startsWith('$label:') ||
              normalized.startsWith('$label :'));

      if (!isStreetLine || i == 0) continue;

      final candidate = lines[i - 1].trim();
      // Linhas de código (NF, rastreio, rota) não são nome de gente.
      if (_looksLikeCode(candidate)) return null;
      return candidate;
    }
    return null;
  }

  bool _looksLikeCode(String line) {
    final digits = line.replaceAll(RegExp(r'\D'), '').length;
    if (line.isEmpty) return true;
    // Mais de 40% de dígitos, ou setas de rota, ou rótulo de nota fiscal.
    if (digits / line.length > 0.4) return true;
    if (line.contains('>')) return true;
    if (RegExp(r'\bNF\b', caseSensitive: false).hasMatch(line)) return true;
    return false;
  }

  // ------------------------------------------------------------- sem rótulo

  ScannedAddress _parseByShape(List<String> lines, String rawText) {
    final cep = _findStandaloneCep(lines);

    String? street;
    String? number;
    String? neighborhood;

    for (final line in lines) {
      if (!_streetPrefix.hasMatch(line)) continue;
      final parts = _splitStreetLine(line);
      street = parts.street;
      number = parts.number;
      neighborhood = parts.neighborhood;
      break;
    }

    if (cep == null && street == null) return ScannedAddress.empty(rawText);

    return ScannedAddress(
      street: street,
      number: number,
      neighborhood: neighborhood,
      cep: cep,
      state: cep == null ? null : CepRangeResolver.ufFor(cep),
      confidence: ScanConfidence.inferred,
      rawText: rawText,
    );
  }

  /// Procura um CEP em linha que não seja parte de um número longo.
  String? _findStandaloneCep(List<String> lines) {
    for (final line in lines) {
      if (_longDigitRun.hasMatch(line)) continue;
      final cep = CepFormatter.extractFrom(line);
      if (cep != null) return cep;
    }
    return null;
  }

  String? _extractCep(String value) {
    if (_longDigitRun.hasMatch(value)) {
      // O rótulo dizia CEP mas o valor é longo demais — provável leitura
      // grudada com o código ao lado. Melhor não chutar.
      return null;
    }
    return CepFormatter.extractFrom(value);
  }

  // ------------------------------------------------------------ logradouro

  /// Separa "Rua Carlos Ollig 20, Pinheiros" em rua, número e bairro.
  ///
  /// Formatos que aparecem na prática:
  ///   Rua Carlos Ollig 20, Pinheiros      (número grudado, sem vírgula)
  ///   Rua Carlos Ollig, 20, Pinheiros     (número em campo próprio)
  ///   Rua Carlos Ollig, 20 - Pinheiros    (traço separando o bairro)
  ///   Avenida Brasil S/N, Centro          (sem número)
  _StreetParts _splitStreetLine(String line) {
    // O traço também separa bairro em muitas etiquetas.
    final segments = line
        .split(RegExp(r'[,;]|\s-\s'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (segments.isEmpty) return const _StreetParts();

    var street = segments.first;
    String? number;
    String? neighborhood;

    // Número em segmento próprio: "Rua X, 20, Bairro".
    if (segments.length > 1 && _isNumberToken(segments[1])) {
      number = _cleanNumber(segments[1]);
      neighborhood = segments.length > 2 ? segments[2] : null;
    } else {
      // Número grudado no fim da rua: "Rua Carlos Ollig 20".
      final trailing =
          RegExp(r'^(.*?)[\s,]+(\d+[a-zA-Z]?|s/?n\.?)$', caseSensitive: false)
              .firstMatch(street);

      if (trailing != null) {
        street = trailing.group(1)!.trim();
        number = _cleanNumber(trailing.group(2)!);
      }
      neighborhood = segments.length > 1 ? segments[1] : null;
    }

    return _StreetParts(
      street: street.isEmpty ? null : street,
      number: number,
      neighborhood: neighborhood,
    );
  }

  bool _isNumberToken(String value) =>
      RegExp(r'^(\d+[a-zA-Z]?|s/?n\.?)$', caseSensitive: false)
          .hasMatch(value.trim());

  /// "S/N" vira null: melhor campo vazio do que um número que não existe.
  String? _cleanNumber(String value) {
    final trimmed = value.trim();
    if (RegExp(r'^s/?n\.?$', caseSensitive: false).hasMatch(trimmed)) {
      return null;
    }
    return trimmed;
  }

  /// "Apiai, São Paulo" -> cidade + UF.
  _CityParts _splitCityLine(String? line) {
    if (line == null) return const _CityParts();

    final segments =
        line.split(RegExp(r'[,/-]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    if (segments.isEmpty) return const _CityParts();
    if (segments.length == 1) return _CityParts(city: segments.first);

    return _CityParts(
      city: segments.first,
      state: BrazilStates.toUf(segments.last),
    );
  }
}

class _StreetParts {
  final String? street;
  final String? number;
  final String? neighborhood;

  const _StreetParts({this.street, this.number, this.neighborhood});
}

class _CityParts {
  final String? city;
  final String? state;

  const _CityParts({this.city, this.state});
}
