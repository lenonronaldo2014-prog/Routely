import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';

/// Exporta e importa os dados do app como um arquivo de texto.
///
/// É a resposta sem servidor para "troquei de celular e perdi tudo": o usuário
/// gera um arquivo, manda para si mesmo por WhatsApp ou e-mail, e importa no
/// aparelho novo. Zero infraestrutura, zero custo, e ele fica dono do próprio
/// backup.
///
/// A base de CEP **não** entra no arquivo de propósito: são centenas de
/// milhares de linhas que deixariam o backup gigante, e ela é reimportável do
/// arquivo original a qualquer momento.
abstract class BackupDataSource {
  Future<String> export();

  /// Substitui os dados atuais pelos do arquivo. Devolve quantos registros
  /// entraram.
  Future<BackupSummary> import(String content);
}

class BackupSummary {
  final int stops;
  final int history;

  const BackupSummary({required this.stops, required this.history});

  int get total => stops + history;
}

class BackupDataSourceImpl implements BackupDataSource {
  /// Sobe quando o formato mudar de um jeito que a versão antiga não entenda.
  static const int formatVersion = 1;

  final AppDatabase appDatabase;

  BackupDataSourceImpl({required this.appDatabase});

  @override
  Future<String> export() async {
    try {
      final db = await appDatabase.database;

      final payload = {
        'format': 'routely-backup',
        'version': formatVersion,
        'exported_at': DateTime.now().toIso8601String(),
        'stops': await db.query('stops'),
        'history': await db.query('delivery_history'),
      };

      // Indentado para o arquivo ser legível se o usuário abrir — é o backup
      // dele, não uma caixa preta.
      return const JsonEncoder.withIndent('  ').convert(payload);
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<BackupSummary> import(String content) async {
    final Map<String, dynamic> payload;
    try {
      payload = json.decode(content) as Map<String, dynamic>;
    } catch (_) {
      throw BackupFormatException('Arquivo não é um backup do Routely.');
    }

    if (payload['format'] != 'routely-backup') {
      throw BackupFormatException('Arquivo não é um backup do Routely.');
    }

    final version = payload['version'];
    if (version is! int || version > formatVersion) {
      throw BackupFormatException(
        'Esse backup foi feito por uma versão mais nova do app. '
        'Atualize antes de importar.',
      );
    }

    try {
      final db = await appDatabase.database;
      var stops = 0;
      var history = 0;

      // Tudo numa transação: importação pela metade deixaria o usuário com um
      // estado pior do que o que ele tinha.
      await db.transaction((txn) async {
        // A rota em andamento aponta para paradas que estão sendo trocadas —
        // precisa sair junto para não ficar apontando para o vazio.
        await txn.delete('active_route_legs');
        await txn.delete('active_route');
        await txn.delete('stops');
        await txn.delete('delivery_history');

        stops = await _insertAll(txn, 'stops', payload['stops']);
        history = await _insertAll(txn, 'delivery_history', payload['history']);
      });

      return BackupSummary(stops: stops, history: history);
    } on BackupFormatException {
      rethrow;
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  Future<int> _insertAll(
    Transaction txn,
    String table,
    Object? rows,
  ) async {
    if (rows is! List) return 0;

    var inserted = 0;
    for (final row in rows) {
      if (row is! Map) continue;
      try {
        await txn.insert(
          table,
          Map<String, Object?>.from(row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        inserted++;
      } catch (_) {
        // Registro corrompido é pulado: importar 199 de 200 é melhor que
        // abortar tudo por causa de uma linha ruim.
      }
    }
    return inserted;
  }
}

class BackupFormatException implements Exception {
  final String message;
  BackupFormatException(this.message);
}
