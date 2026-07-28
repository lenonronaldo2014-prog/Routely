import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:routely/core/database/app_database.dart';
import 'package:routely/features/stops/data/datasources/cep_directory_local_data_source.dart';
import 'package:routely/features/stops/domain/entities/address_lookup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Base de CEP sintética. O formato é o mesmo do arquivo real:
/// `cep;logradouro;bairro;cidade;uf`
const _spLines = [
  '# base de exemplo — comentário deve ser ignorado',
  '01001-000;Praça da Sé;Sé;São Paulo;SP',
  '01310100;Avenida Paulista;Bela Vista;São Paulo;SP',
  '',
  '13010000;Rua Barão de Jaguara;Centro;Campinas;SP',
  'linha quebrada sem separador',
  '99999;Rua curta demais;Bairro;Cidade;SP',
  '05407-002;Rua Cardeal Arcoverde;Pinheiros;São Paulo;SP',
  // CEP sem logradouro: cidade pequena de logradouro único.
  '19800-000;;;Assis;SP',
];

const _mgLines = [
  '30130-010;Avenida Afonso Pena;Centro;Belo Horizonte;MG',
  '31000-000;Rua Exemplo;Bairro;Belo Horizonte;MG',
];

void main() {
  late AppDatabase appDatabase;
  late CepDirectoryLocalDataSourceImpl directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // Nome próprio para não colidir com o outro arquivo de teste que também usa
  // SQLite — o `flutter test` roda os dois em paralelo.
  const dbName = 'routely_cep_test.db';

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    await databaseFactory
        .deleteDatabase(p.join(await getDatabasesPath(), dbName));
    appDatabase = AppDatabase(databaseName: dbName);
    directory = CepDirectoryLocalDataSourceImpl(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<int> importSp() => directory.importState(
        state: 'SP',
        lines: Stream.fromIterable(_spLines),
        sourceVersion: '2026-07',
      );

  group('CepEntry.tryParse', () {
    test('lê uma linha bem formada', () {
      final entry = CepEntry.tryParse('01001-000;Praça da Sé;Sé;São Paulo;SP');

      expect(entry, isNotNull);
      expect(entry!.cep, '01001000');
      expect(entry.street, 'Praça da Sé');
      expect(entry.neighborhood, 'Sé');
      expect(entry.city, 'São Paulo');
      expect(entry.state, 'SP');
    });

    test('ignora comentário e linha em branco', () {
      expect(CepEntry.tryParse('# comentário'), isNull);
      expect(CepEntry.tryParse('   '), isNull);
      expect(CepEntry.tryParse(''), isNull);
    });

    test('rejeita linha malformada', () {
      expect(CepEntry.tryParse('sem separador nenhum'), isNull);
      expect(CepEntry.tryParse('01001000;Rua;Bairro'), isNull);
      expect(CepEntry.tryParse('123;Rua;Bairro;Cidade;SP'), isNull);
      expect(CepEntry.tryParse('01001000;Rua;Bairro;Cidade;XPTO'), isNull);
      expect(CepEntry.tryParse('01001000;Rua;Bairro;;SP'), isNull);
    });

    test('aceita logradouro vazio', () {
      final entry = CepEntry.tryParse('19800-000;;;Assis;SP');

      expect(entry, isNotNull);
      expect(entry!.street, isEmpty);
      expect(entry.city, 'Assis');
    });
  });

  group('importação', () {
    test('importa só as linhas válidas', () async {
      final imported = await importSp();

      // 8 linhas de conteúdo, 3 inválidas (comentário, vazia, quebrada e CEP
      // curto contam como descartadas).
      expect(imported, 5);
    });

    test('linha ruim não aborta a importação', () async {
      await importSp();

      // As entradas depois da linha quebrada precisam ter entrado.
      final lookup = await directory.lookup('05407002');
      expect(lookup, isNotNull);
      expect(lookup!.street, 'Rua Cardeal Arcoverde');
    });

    test('registra o pacote instalado', () async {
      await importSp();

      final packs = await directory.installedPacks();

      expect(packs, hasLength(1));
      expect(packs.first.state, 'SP');
      expect(packs.first.entryCount, 5);
      expect(packs.first.sourceVersion, '2026-07');
    });

    test('descarta entradas de outro estado', () async {
      final imported = await directory.importState(
        state: 'SP',
        lines: Stream.fromIterable([..._spLines, ..._mgLines]),
      );

      expect(imported, 5);
      expect(await directory.lookup('30130010'), isNull);
    });

    test('estados convivem lado a lado', () async {
      await importSp();
      await directory.importState(
        state: 'MG',
        lines: Stream.fromIterable(_mgLines),
      );

      expect((await directory.lookup('01001000'))?.state, 'SP');
      expect((await directory.lookup('30130010'))?.state, 'MG');
      expect(await directory.installedPacks(), hasLength(2));
    });

    // Base meio atualizada seria pior que nenhuma: o usuário confiaria num
    // dado velho sem saber.
    test('reimportar substitui em vez de somar', () async {
      await importSp();
      await directory.importState(
        state: 'SP',
        lines: Stream.fromIterable([
          '01001-000;Praça da Sé (novo nome);Sé;São Paulo;SP',
        ]),
      );

      final packs = await directory.installedPacks();
      expect(packs.first.entryCount, 1);

      expect((await directory.lookup('01001000'))?.street,
          'Praça da Sé (novo nome)');
      expect(
        await directory.lookup('01310100'),
        isNull,
        reason: 'entrada da importação anterior não pode sobrar',
      );
    });

    test('reimportar um estado não mexe no outro', () async {
      await importSp();
      await directory.importState(
        state: 'MG',
        lines: Stream.fromIterable(_mgLines),
      );

      await directory.importState(
        state: 'SP',
        lines: Stream.fromIterable(['01001-000;Praça da Sé;Sé;São Paulo;SP']),
      );

      expect(await directory.lookup('30130010'), isNotNull);
    });

    test('reporta progresso durante a importação', () async {
      final progress = <int>[];

      await directory.importState(
        state: 'SP',
        lines: Stream.fromIterable(_spLines),
        onProgress: (p) => progress.add(p.processed),
      );

      expect(progress, isNotEmpty);
      expect(progress.last, 5);
    });
  });

  group('consulta', () {
    setUp(() => importSp());

    test('encontra o endereço sem rede', () async {
      final lookup = await directory.lookup('01310100');

      expect(lookup, isNotNull);
      expect(lookup!.street, 'Avenida Paulista');
      expect(lookup.neighborhood, 'Bela Vista');
      expect(lookup.city, 'São Paulo');
      expect(lookup.state, 'SP');
      expect(lookup.source, AddressSource.localDirectory);
      expect(lookup.source.isOffline, isTrue);
      expect(lookup.source.isPartial, isFalse);
    });

    test('aceita CEP com máscara na consulta', () async {
      expect(await directory.lookup('01310-100'), isNotNull);
    });

    test('CEP fora da base devolve null', () async {
      expect(await directory.lookup('99999999'), isNull);
    });

    test('CEP de logradouro único volta sem rua mas com cidade', () async {
      final lookup = await directory.lookup('19800000');

      expect(lookup, isNotNull);
      expect(lookup!.hasStreet, isFalse);
      expect(lookup.hasCity, isTrue);
      expect(lookup.city, 'Assis');
    });
  });

  group('remoção', () {
    test('remover libera o espaço do estado', () async {
      await importSp();
      await directory.importState(
        state: 'MG',
        lines: Stream.fromIterable(_mgLines),
      );

      await directory.removeState('SP');

      expect(await directory.lookup('01001000'), isNull);
      expect(await directory.lookup('30130010'), isNotNull);

      final packs = await directory.installedPacks();
      expect(packs, hasLength(1));
      expect(packs.first.state, 'MG');
    });

    test('remover estado não instalado não quebra', () async {
      await directory.removeState('BA');
      expect(await directory.installedPacks(), isEmpty);
    });
  });
}
