import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/geo/geo_point.dart';
import '../../../../core/util/cep_formatter.dart';
import '../../domain/entities/address_lookup.dart';
import '../../domain/entities/cep_pack.dart';

/// Uma linha do arquivo de importação.
class CepEntry {
  final String cep;
  final String street;
  final String neighborhood;
  final String city;
  final String state;

  /// Opcionais. Quando vêm, o app resolve o endereço em coordenada **sem
  /// rede e sem custo** — é o que permite operar em escala de graça.
  final double? latitude;
  final double? longitude;

  const CepEntry({
    required this.cep,
    required this.street,
    required this.neighborhood,
    required this.city,
    required this.state,
    this.latitude,
    this.longitude,
  });

  bool get hasCoordinate => latitude != null && longitude != null;

  /// Formato do arquivo, um CEP por linha, separador `;`:
  ///
  ///   cep;logradouro;bairro;cidade;uf
  ///   cep;logradouro;bairro;cidade;uf;latitude;longitude
  ///
  /// As duas últimas colunas são opcionais — arquivo antigo de 5 colunas
  /// continua válido. Linhas em branco e comentários (`#`) são ignorados.
  ///
  /// Ponto e vírgula porque logradouro brasileiro tem vírgula com frequência
  /// ("Rua Ipiranga, lado par") e escapar CSV de verdade seria custo sem
  /// retorno para um formato que nós mesmos geramos.
  static CepEntry? tryParse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;

    final parts = trimmed.split(';');
    if (parts.length < 5) return null;

    final cep = CepFormatter.normalize(parts[0]);
    if (cep.length != 8) return null;

    final state = parts[4].trim().toUpperCase();
    if (state.length != 2) return null;

    final city = parts[3].trim();
    if (city.isEmpty) return null;

    return CepEntry(
      cep: cep,
      street: parts[1].trim(),
      neighborhood: parts[2].trim(),
      city: city,
      state: state,
      latitude: parts.length > 5 ? _parseCoordinate(parts[5], 90) : null,
      longitude: parts.length > 6 ? _parseCoordinate(parts[6], 180) : null,
    );
  }

  /// Coordenada fora de faixa é lixo de conversão — melhor descartar do que
  /// mandar o entregador para o oceano.
  static double? _parseCoordinate(String raw, double limit) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (value == null) return null;
    if (value.abs() > limit) return null;
    if (value == 0) return null;
    return value;
  }
}

abstract class CepDirectoryLocalDataSource {
  /// Consulta na base instalada. Null quando o CEP não está lá.
  Future<AddressLookup?> lookup(String cep);

  /// Importa as entradas de um estado. Devolve quantas foram gravadas.
  Future<int> importState({
    required String state,
    required Stream<String> lines,
    String? sourceVersion,
    void Function(CepImportProgress progress)? onProgress,
  });

  Future<List<CepPack>> installedPacks();

  Future<void> removeState(String state);
}

class CepDirectoryLocalDataSourceImpl implements CepDirectoryLocalDataSource {
  /// Quantas linhas por transação. Uma transação por linha deixaria a
  /// importação de uma base estadual absurdamente lenta; uma transação única
  /// para tudo estouraria a memória e perderia todo o trabalho num erro no
  /// fim. Lotes dão os dois: rápido e recuperável.
  static const int _batchSize = 2000;

  final AppDatabase appDatabase;

  CepDirectoryLocalDataSourceImpl({required this.appDatabase});

  @override
  Future<AddressLookup?> lookup(String cep) async {
    try {
      final db = await appDatabase.database;
      final rows = await db.query(
        'cep_directory',
        where: 'cep = ?',
        whereArgs: [CepFormatter.normalize(cep)],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final row = rows.first;
      final lat = row['latitude'] as double?;
      final lng = row['longitude'] as double?;

      return AddressLookup(
        cep: row['cep'] as String,
        street: (row['street'] as String?) ?? '',
        neighborhood: (row['neighborhood'] as String?) ?? '',
        city: row['city'] as String,
        state: row['state'] as String,
        coordinate: (lat != null && lng != null)
            ? GeoPoint(latitude: lat, longitude: lng)
            : null,
        source: AddressSource.localDirectory,
      );
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<int> importState({
    required String state,
    required Stream<String> lines,
    String? sourceVersion,
    void Function(CepImportProgress progress)? onProgress,
  }) async {
    final uf = state.trim().toUpperCase();

    try {
      final db = await appDatabase.database;

      // Reimportar substitui: base parcialmente atualizada seria pior que
      // nenhuma, porque o usuário confiaria num dado velho sem saber.
      await db.delete('cep_directory', where: 'state = ?', whereArgs: [uf]);

      var imported = 0;
      var buffer = <CepEntry>[];

      Future<void> flush() async {
        if (buffer.isEmpty) return;
        final batch = buffer;
        buffer = <CepEntry>[];

        await db.transaction((txn) async {
          final b = txn.batch();
          for (final entry in batch) {
            b.insert(
              'cep_directory',
              {
                'cep': entry.cep,
                'street': entry.street,
                'neighborhood': entry.neighborhood,
                'city': entry.city,
                'state': entry.state,
                'latitude': entry.latitude,
                'longitude': entry.longitude,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await b.commit(noResult: true);
        });

        imported += batch.length;
        onProgress?.call(CepImportProgress(processed: imported));
      }

      await for (final line in lines) {
        final entry = CepEntry.tryParse(line);
        // Linha malformada é pulada em silêncio: base pública tem lixo, e
        // abortar a importação inteira por causa de uma linha ruim seria pior
        // para o usuário do que importar as outras 400 mil.
        if (entry == null) continue;
        if (entry.state != uf) continue;

        buffer.add(entry);
        if (buffer.length >= _batchSize) await flush();
      }
      await flush();

      await db.insert(
        'cep_directory_packs',
        {
          'state': uf,
          'entry_count': imported,
          'imported_at': DateTime.now().millisecondsSinceEpoch,
          'source_version': sourceVersion,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return imported;
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<List<CepPack>> installedPacks() async {
    try {
      final db = await appDatabase.database;
      final rows = await db.query('cep_directory_packs', orderBy: 'state ASC');

      return rows
          .map((row) => CepPack(
                state: row['state'] as String,
                entryCount: row['entry_count'] as int,
                importedAt: DateTime.fromMillisecondsSinceEpoch(
                  row['imported_at'] as int,
                ),
                sourceVersion: row['source_version'] as String?,
              ))
          .toList();
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> removeState(String state) async {
    final uf = state.trim().toUpperCase();
    try {
      final db = await appDatabase.database;
      await db.transaction((txn) async {
        await txn.delete('cep_directory', where: 'state = ?', whereArgs: [uf]);
        await txn.delete(
          'cep_directory_packs',
          where: 'state = ?',
          whereArgs: [uf],
        );
      });
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }
}
