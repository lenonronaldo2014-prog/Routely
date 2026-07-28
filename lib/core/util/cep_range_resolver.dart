import 'cep_formatter.dart';

/// Uma faixa contínua de CEP atribuída a um estado.
class CepRange {
  /// Primeiros 5 dígitos, inclusive.
  final int start;

  /// Primeiros 5 dígitos, inclusive.
  final int end;

  final String uf;

  const CepRange(this.start, this.end, this.uf);

  bool contains(int prefix) => prefix >= start && prefix <= end;
}

/// Descobre o estado a partir do CEP, **sem rede e sem nenhum arquivo de
/// dados**.
///
/// O CEP brasileiro não é um número arbitrário: a primeira metade codifica
/// região e sub-região, e a alocação por estado é pública e estável. Isso dá de
/// graça três coisas úteis offline:
///
/// 1. validar o que o usuário digitou (CEP de SP num roteiro de Minas é erro
///    de digitação, quase sempre);
/// 2. preencher a UF na hora, sem esperar rede;
/// 3. um resultado parcial honesto quando não há internet nem base local —
///    melhor "identificamos o estado" do que uma tela de erro.
///
/// Faixas não atribuídas devolvem `null` de propósito. Chutar o estado vizinho
/// seria pior do que admitir que não sabe.
class CepRangeResolver {
  CepRangeResolver._();

  /// Alocação por UF, em prefixos de 5 dígitos.
  ///
  /// Alguns estados aparecem em mais de uma faixa: DF e GO se intercalam, e
  /// AM é cortado ao meio por RR. Não é engano — é como a numeração foi
  /// distribuída.
  static const List<CepRange> ranges = [
    CepRange(1000, 19999, 'SP'),
    CepRange(20000, 28999, 'RJ'),
    CepRange(29000, 29999, 'ES'),
    CepRange(30000, 39999, 'MG'),
    CepRange(40000, 48999, 'BA'),
    CepRange(49000, 49999, 'SE'),
    CepRange(50000, 56999, 'PE'),
    CepRange(57000, 57999, 'AL'),
    CepRange(58000, 58999, 'PB'),
    CepRange(59000, 59999, 'RN'),
    CepRange(60000, 63999, 'CE'),
    CepRange(64000, 64999, 'PI'),
    CepRange(65000, 65999, 'MA'),
    CepRange(66000, 68899, 'PA'),
    CepRange(68900, 68999, 'AP'),
    CepRange(69000, 69299, 'AM'),
    CepRange(69300, 69399, 'RR'),
    CepRange(69400, 69899, 'AM'),
    CepRange(69900, 69999, 'AC'),
    CepRange(70000, 72799, 'DF'),
    CepRange(72800, 72999, 'GO'),
    CepRange(73000, 73699, 'DF'),
    CepRange(73700, 76799, 'GO'),
    CepRange(76800, 76999, 'RO'),
    CepRange(77000, 77999, 'TO'),
    CepRange(78000, 78899, 'MT'),
    CepRange(79000, 79999, 'MS'),
    CepRange(80000, 87999, 'PR'),
    CepRange(88000, 89999, 'SC'),
    CepRange(90000, 99999, 'RS'),
  ];

  /// UF do CEP, ou null se o CEP for inválido ou cair numa faixa não atribuída.
  static String? ufFor(String cep) {
    final digits = CepFormatter.normalize(cep);
    if (digits.length != 8) return null;

    final prefix = int.tryParse(digits.substring(0, 5));
    if (prefix == null) return null;

    for (final range in ranges) {
      if (range.contains(prefix)) return range.uf;
    }
    return null;
  }

  /// `true` quando o CEP claramente não pertence à UF informada.
  ///
  /// Devolve `false` quando não dá para afirmar — faixa não atribuída ou UF
  /// vazia. Acusar erro sem certeza atrapalharia mais do que ajuda.
  static bool contradicts(String cep, String? uf) {
    if (uf == null || uf.trim().isEmpty) return false;

    final expected = ufFor(cep);
    if (expected == null) return false;

    return expected.toUpperCase() != uf.trim().toUpperCase();
  }
}
