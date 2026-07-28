import 'package:flutter_test/flutter_test.dart';
import 'package:routely/core/util/cep_range_resolver.dart';

void main() {
  group('CepRangeResolver.ufFor', () {
    test('resolve capitais conhecidas', () {
      expect(CepRangeResolver.ufFor('01001000'), 'SP'); // Praça da Sé
      expect(CepRangeResolver.ufFor('20040002'), 'RJ'); // Centro, Rio
      expect(CepRangeResolver.ufFor('30130010'), 'MG'); // Belo Horizonte
      expect(CepRangeResolver.ufFor('40020000'), 'BA'); // Salvador
      expect(CepRangeResolver.ufFor('80010000'), 'PR'); // Curitiba
      expect(CepRangeResolver.ufFor('90010000'), 'RS'); // Porto Alegre
      expect(CepRangeResolver.ufFor('70040900'), 'DF'); // Brasília
    });

    test('aceita CEP com máscara', () {
      expect(CepRangeResolver.ufFor('01001-000'), 'SP');
      expect(CepRangeResolver.ufFor('13010-000'), 'SP');
    });

    test('respeita os limites das faixas', () {
      // Fim de SP / começo de RJ.
      expect(CepRangeResolver.ufFor('19999999'), 'SP');
      expect(CepRangeResolver.ufFor('20000000'), 'RJ');

      // Fim de RJ / começo de ES.
      expect(CepRangeResolver.ufFor('28999999'), 'RJ');
      expect(CepRangeResolver.ufFor('29000000'), 'ES');

      // Fim de SC / começo de RS.
      expect(CepRangeResolver.ufFor('89999999'), 'SC');
      expect(CepRangeResolver.ufFor('90000000'), 'RS');
    });

    // DF e GO se intercalam — é o trecho mais fácil de errar.
    test('separa DF e GO nas duas faixas de cada um', () {
      expect(CepRangeResolver.ufFor('70000000'), 'DF');
      expect(CepRangeResolver.ufFor('72799999'), 'DF');
      expect(CepRangeResolver.ufFor('72800000'), 'GO');
      expect(CepRangeResolver.ufFor('72999999'), 'GO');
      expect(CepRangeResolver.ufFor('73000000'), 'DF');
      expect(CepRangeResolver.ufFor('73699999'), 'DF');
      expect(CepRangeResolver.ufFor('73700000'), 'GO');
      expect(CepRangeResolver.ufFor('76799999'), 'GO');
    });

    // RR corta a faixa do AM ao meio.
    test('separa AM e RR', () {
      expect(CepRangeResolver.ufFor('69000000'), 'AM');
      expect(CepRangeResolver.ufFor('69299999'), 'AM');
      expect(CepRangeResolver.ufFor('69300000'), 'RR');
      expect(CepRangeResolver.ufFor('69399999'), 'RR');
      expect(CepRangeResolver.ufFor('69400000'), 'AM');
      expect(CepRangeResolver.ufFor('69899999'), 'AM');
      expect(CepRangeResolver.ufFor('69900000'), 'AC');
    });

    test('CEP inválido devolve null', () {
      expect(CepRangeResolver.ufFor(''), isNull);
      expect(CepRangeResolver.ufFor('123'), isNull);
      expect(CepRangeResolver.ufFor('1234567890'), isNull);
      expect(CepRangeResolver.ufFor('abcdefgh'), isNull);
    });

    // Preferimos admitir que não sabemos a chutar o estado vizinho.
    test('faixa não atribuída devolve null em vez de chutar', () {
      expect(CepRangeResolver.ufFor('00500000'), isNull);
    });

    test('toda faixa declarada resolve para a própria UF', () {
      for (final range in CepRangeResolver.ranges) {
        final start = range.start.toString().padLeft(5, '0');
        final end = range.end.toString().padLeft(5, '0');

        expect(CepRangeResolver.ufFor('${start}000'), range.uf);
        expect(CepRangeResolver.ufFor('${end}999'), range.uf);
      }
    });

    test('as faixas não se sobrepõem', () {
      final sorted = [...CepRangeResolver.ranges]
        ..sort((a, b) => a.start.compareTo(b.start));

      for (var i = 1; i < sorted.length; i++) {
        expect(
          sorted[i].start,
          greaterThan(sorted[i - 1].end),
          reason: 'faixa de ${sorted[i].uf} invade a de ${sorted[i - 1].uf}',
        );
      }
    });
  });

  group('CepRangeResolver.contradicts', () {
    test('acusa CEP de outro estado', () {
      expect(CepRangeResolver.contradicts('01001000', 'MG'), isTrue);
      expect(CepRangeResolver.contradicts('30130010', 'SP'), isTrue);
    });

    test('não acusa quando bate', () {
      expect(CepRangeResolver.contradicts('01001000', 'SP'), isFalse);
      expect(CepRangeResolver.contradicts('01001000', 'sp'), isFalse);
      expect(CepRangeResolver.contradicts('01001000', ' SP '), isFalse);
    });

    // Sem certeza, ficar quieto: alerta falso atrapalha mais do que ajuda.
    test('não acusa quando não dá para afirmar', () {
      expect(CepRangeResolver.contradicts('01001000', null), isFalse);
      expect(CepRangeResolver.contradicts('01001000', ''), isFalse);
      expect(CepRangeResolver.contradicts('00500000', 'SP'), isFalse);
      expect(CepRangeResolver.contradicts('123', 'SP'), isFalse);
    });
  });
}
