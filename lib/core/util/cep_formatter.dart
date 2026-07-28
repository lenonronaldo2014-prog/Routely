/// Utilitários de CEP.
///
/// O CEP é a peça mais valiosa de um endereço brasileiro para o app: tem
/// formato rígido (8 dígitos), o que o torna uma âncora confiável tanto para
/// validar o que o usuário digita quanto, mais à frente, para extrair endereço
/// de uma etiqueta via OCR.
class CepFormatter {
  CepFormatter._();

  static final _digitsOnly = RegExp(r'\D');

  /// Encontra um CEP dentro de um texto qualquer — útil para colar endereço
  /// copiado de outro app, e depois para o OCR da etiqueta.
  static final pattern = RegExp(r'\b(\d{5})-?(\d{3})\b');

  /// Remove máscara: "13010-000" -> "13010000".
  static String normalize(String value) => value.replaceAll(_digitsOnly, '');

  /// Aplica máscara: "13010000" -> "13010-000".
  static String mask(String value) {
    final digits = normalize(value);
    if (digits.length <= 5) return digits;
    final head = digits.substring(0, 5);
    final tail = digits.substring(5, digits.length.clamp(5, 8));
    return '$head-$tail';
  }

  static bool isValid(String value) => normalize(value).length == 8;

  /// Extrai o primeiro CEP de um texto livre, ou null.
  static String? extractFrom(String text) {
    final match = pattern.firstMatch(text);
    if (match == null) return null;
    return '${match.group(1)}${match.group(2)}';
  }
}
