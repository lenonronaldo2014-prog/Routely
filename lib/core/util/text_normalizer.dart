/// Normalização de texto para casar rótulos vindos de OCR.
///
/// OCR erra acento com frequência: "Endereço" volta como "Endereco",
/// "Endereço" ou "Enderaço" dependendo da luz e do amassado no plástico.
/// Comparar sem acento e sem caixa evita que o parser inteiro falhe por causa
/// de uma cedilha.
class TextNormalizer {
  TextNormalizer._();

  static const _accents = {
    'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };

  /// Minúsculas, sem acento e com espaços colapsados.
  static String normalize(String value) {
    final lower = value.toLowerCase();
    final buffer = StringBuffer();

    for (final char in lower.split('')) {
      buffer.write(_accents[char] ?? char);
    }

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Colapsa espaços preservando acentos e caixa — para o texto que vai ser
  /// mostrado ao usuário.
  static String collapseSpaces(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
