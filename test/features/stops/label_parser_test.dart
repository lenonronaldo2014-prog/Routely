import 'package:flutter_test/flutter_test.dart';
import 'package:routely/features/stops/domain/entities/scanned_address.dart';
import 'package:routely/features/stops/domain/services/label_parser.dart';

/// Etiqueta 1 — Mercado Livre, foto de frente e bem iluminada.
/// Transcrição do que o OCR devolveria, na ordem de leitura.
const _mercadoLivre1 = '''
47612168549
3SSP27
20:00
FSP15 > XSP17 > SSP27 > ESP19 > X10
TER 28/07/2026
NF: 25613
Rodrigo Dall Agnol (CONSTRUBASEAPIAI)
Endereço: Rua Carlos Ollig 20, Pinheiros
CEP: 18320620
Cidade de destino: Apiai, São Paulo
Complemento: Sobrado esquina
''';

/// Etiqueta 2 — mesmo destinatário, outro pacote. O que muda e importa: o
/// endereço do **remetente** aparece na borda, sem rótulo, com outro CEP
/// (Guarulhos, 07174530). E tem a chave do DANFE, 44 dígitos.
const _mercadoLivre2 = '''
Makram Produtos #18336693316
Avenida Francisco Xavier Correa S/N. Residencial
Parque Cumbica
Guarulhos, BR-SP - 07174530
Venda: 20000175998851922
SP19
37 SSP27
01:00
47611367074
SP19 > SSP27 > ESP19 > X10
TER 28/07/2026
NF: 199077
Rodrigo Dall Agnol (CONSTRUBASEAPIAI)
Endereço: Rua Carlos Ollig 20, Pinheiros
CEP: 18320620
Cidade de destino: Apiai, São Paulo
Complemento: Sobrado esquina
DANFE SIMPLIFICADO
Chave de acesso 35260755556644000152550020001990771967010770
''';

void main() {
  const parser = LabelParser();

  group('etiqueta 1 do Mercado Livre', () {
    late ScannedAddress result;

    setUp(() => result = parser.parse(_mercadoLivre1));

    test('reconhece como etiqueta rotulada', () {
      expect(result.confidence, ScanConfidence.labelled);
      expect(result.hasAnything, isTrue);
    });

    test('separa rua e número grudados', () {
      expect(result.street, 'Rua Carlos Ollig');
      expect(result.number, '20');
    });

    test('lê bairro, cidade e UF', () {
      expect(result.neighborhood, 'Pinheiros');
      expect(result.city, 'Apiai');
      expect(result.state, 'SP');
    });

    test('lê o CEP sem máscara', () {
      expect(result.cep, '18320620');
    });

    test('lê o complemento', () {
      expect(result.complement, 'Sobrado esquina');
    });

    test('pega o nome como apelido da entrega', () {
      expect(result.recipient, 'Rodrigo Dall Agnol (CONSTRUBASEAPIAI)');
    });

    test('tem CEP e número, que já bastam para montar o endereço', () {
      expect(result.hasCepAndNumber, isTrue);
    });
  });

  group('etiqueta 2 — com remetente e chave do DANFE', () {
    late ScannedAddress result;

    setUp(() => result = parser.parse(_mercadoLivre2));

    // O erro mais caro possível: mandar o entregador para o remetente.
    test('pega o CEP do destinatário, não o do remetente', () {
      expect(result.cep, '18320620');
      expect(
        result.cep,
        isNot('07174530'),
        reason: 'esse é o CEP do remetente, em Guarulhos',
      );
    });

    test('ignora a chave de 44 dígitos do DANFE', () {
      expect(result.cep, '18320620');
    });

    test('pega o endereço do destinatário, não o da borda', () {
      expect(result.street, 'Rua Carlos Ollig');
      expect(result.number, '20');
      expect(
        result.street,
        isNot(contains('Francisco Xavier')),
        reason: 'esse é o logradouro do remetente',
      );
    });

    test('cidade e UF vêm do destino', () {
      expect(result.city, 'Apiai');
      expect(result.state, 'SP');
    });

    test('as duas etiquetas do mesmo destino dão o mesmo endereço', () {
      final first = parser.parse(_mercadoLivre1);

      expect(result.street, first.street);
      expect(result.number, first.number);
      expect(result.cep, first.cep);
      expect(result.city, first.city);
    });
  });

  group('variações de formato do logradouro', () {
    ScannedAddress parseAddress(String line) =>
        parser.parse('Endereço: $line\nCEP: 01310100');

    test('número em campo próprio', () {
      final result = parseAddress('Rua Augusta, 900, Consolação');
      expect(result.street, 'Rua Augusta');
      expect(result.number, '900');
      expect(result.neighborhood, 'Consolação');
    });

    test('traço separando o bairro', () {
      final result = parseAddress('Avenida Paulista, 1578 - Bela Vista');
      expect(result.street, 'Avenida Paulista');
      expect(result.number, '1578');
      expect(result.neighborhood, 'Bela Vista');
    });

    test('número com letra', () {
      final result = parseAddress('Rua das Flores 123A, Centro');
      expect(result.number, '123A');
    });

    test('sem número deixa o campo vazio em vez de inventar', () {
      final result = parseAddress('Avenida Brasil S/N, Centro');
      expect(result.street, 'Avenida Brasil');
      expect(result.number, isNull);
      expect(result.neighborhood, 'Centro');
    });

    test('só a rua, sem bairro', () {
      final result = parseAddress('Rua Sem Bairro 45');
      expect(result.street, 'Rua Sem Bairro');
      expect(result.number, '45');
      expect(result.neighborhood, isNull);
    });
  });

  group('OCR sem acento', () {
    test('rótulos ainda são reconhecidos', () {
      final result = parser.parse('''
Endereco: Rua Carlos Ollig 20, Pinheiros
CEP: 18320620
Cidade de destino: Apiai, Sao Paulo
Complemento: Sobrado esquina
''');

      expect(result.confidence, ScanConfidence.labelled);
      expect(result.street, 'Rua Carlos Ollig');
      expect(result.cep, '18320620');
      expect(result.state, 'SP');
    });
  });

  group('etiqueta sem rótulo', () {
    test('acha o CEP e o logradouro pelo formato', () {
      final result = parser.parse('''
TRANSPORTADORA XYZ
Joao da Silva
Rua Sete de Setembro 450
Centro
88010-000
Florianopolis SC
''');

      expect(result.confidence, ScanConfidence.inferred);
      expect(result.street, 'Rua Sete de Setembro');
      expect(result.number, '450');
      expect(result.cep, '88010000');
      expect(result.state, 'SC', reason: 'deduzido da faixa do CEP');
    });

    test('não confunde código longo com CEP', () {
      final result = parser.parse('''
Rastreio 35260755556644000152550020
Rua Alfa 10
''');

      expect(result.cep, isNull);
      expect(result.street, 'Rua Alfa');
    });
  });

  group('entradas ruins', () {
    test('texto vazio não quebra', () {
      final result = parser.parse('');
      expect(result.confidence, ScanConfidence.none);
      expect(result.hasAnything, isFalse);
    });

    test('só ruído devolve nada em vez de inventar', () {
      final result = parser.parse('''
||||| |||| ||||
47612168549
20:00
''');

      expect(result.confidence, ScanConfidence.none);
      expect(result.hasAnything, isFalse);
    });

    test('guarda o texto cru para a tela de conferência', () {
      const raw = 'qualquer coisa ilegível';
      expect(parser.parse(raw).rawText, raw);
    });
  });

  group('UF pelo nome por extenso', () {
    test('converte os estados escritos por extenso', () {
      final result = parser.parse('''
Endereço: Rua Um 1, Centro
CEP: 30130010
Cidade de destino: Belo Horizonte, Minas Gerais
''');

      expect(result.state, 'MG');
    });

    test('sem linha de cidade, cai na faixa do CEP', () {
      final result = parser.parse('''
Endereço: Rua Um 1, Centro
CEP: 20040002
''');

      expect(result.state, 'RJ');
    });
  });
}
