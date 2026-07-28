import 'text_normalizer.dart';

/// Conversão entre nome do estado e sigla.
///
/// A etiqueta do Mercado Livre escreve o estado por extenso
/// ("Cidade de destino: Apiai, São Paulo"), enquanto o app trabalha com a
/// sigla. Sem essa tabela o campo UF ficaria vazio justamente quando o resto
/// foi lido com sucesso.
class BrazilStates {
  BrazilStates._();

  static const byName = <String, String>{
    'acre': 'AC',
    'alagoas': 'AL',
    'amapa': 'AP',
    'amazonas': 'AM',
    'bahia': 'BA',
    'ceara': 'CE',
    'distrito federal': 'DF',
    'espirito santo': 'ES',
    'goias': 'GO',
    'maranhao': 'MA',
    'mato grosso': 'MT',
    'mato grosso do sul': 'MS',
    'minas gerais': 'MG',
    'para': 'PA',
    'paraiba': 'PB',
    'parana': 'PR',
    'pernambuco': 'PE',
    'piaui': 'PI',
    'rio de janeiro': 'RJ',
    'rio grande do norte': 'RN',
    'rio grande do sul': 'RS',
    'rondonia': 'RO',
    'roraima': 'RR',
    'santa catarina': 'SC',
    'sao paulo': 'SP',
    'sergipe': 'SE',
    'tocantins': 'TO',
  };

  static final _validUfs = byName.values.toSet();

  /// Aceita tanto "São Paulo" quanto "SP". Devolve null se não reconhecer.
  static String? toUf(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.length == 2) {
      final upper = trimmed.toUpperCase();
      return _validUfs.contains(upper) ? upper : null;
    }

    return byName[TextNormalizer.normalize(trimmed)];
  }
}
