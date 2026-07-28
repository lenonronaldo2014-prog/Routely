import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Banco local do app. O Routely é offline-first: tudo é gravado aqui primeiro
/// e só depois (quando/se houver rede) sincronizado ou enriquecido.
class AppDatabase {
  static const defaultDatabaseName = 'routely.db';
  static const _dbVersion = 4;

  /// Configurável só para teste: o `flutter test` roda arquivos em paralelo, e
  /// dois testes abrindo o mesmo arquivo de banco davam falha intermitente —
  /// um apagava o banco enquanto o outro escrevia. Em produção sempre usa o
  /// nome padrão.
  final String databaseName;

  AppDatabase({this.databaseName = defaultDatabaseName});

  Database? _db;

  Future<Database> get database async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), databaseName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// O sqflite desliga chaves estrangeiras por padrão. Sem isso o
  /// `ON DELETE CASCADE` dos trechos da rota não roda e apagar uma parada
  /// deixaria trecho órfão apontando para nada.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE stops (
        id             TEXT    PRIMARY KEY,
        label          TEXT,
        street         TEXT    NOT NULL,
        number         TEXT,
        complement     TEXT,
        neighborhood   TEXT,
        city           TEXT,
        state          TEXT,
        cep            TEXT,
        latitude       REAL,
        longitude      REAL,
        notes          TEXT,
        status         TEXT    NOT NULL DEFAULT 'pending',
        created_at     INTEGER NOT NULL,
        completed_at   INTEGER
      )
    ''');

    await db.execute('CREATE INDEX idx_stops_status ON stops(status)');

    // Cache de CEP -> logradouro. Evita bater no ViaCEP de novo e é o que
    // permite resolver endereço sem rede depois do primeiro uso.
    await db.execute('''
      CREATE TABLE cep_cache (
        cep            TEXT    PRIMARY KEY,
        street         TEXT,
        neighborhood   TEXT,
        city           TEXT,
        state          TEXT,
        cached_at      INTEGER NOT NULL
      )
    ''');

    // Cache de geocoding: endereço normalizado -> coordenada. Entregador
    // repete muito endereço, então isso corta a maior parte das chamadas.
    await db.execute('''
      CREATE TABLE geocode_cache (
        address_key    TEXT    PRIMARY KEY,
        latitude       REAL    NOT NULL,
        longitude      REAL    NOT NULL,
        cached_at      INTEGER NOT NULL
      )
    ''');

    await _createActiveRouteTables(db);
    await _createCepDirectoryTables(db);
    await _addCepCoordinates(db);
    await _createHistoryTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createActiveRouteTables(db);
    }
    if (oldVersion < 3) {
      await _createCepDirectoryTables(db);
    }
    if (oldVersion < 4) {
      await _addCepCoordinates(db);
      await _createHistoryTable(db);
    }
  }

  /// Coordenada junto do CEP.
  ///
  /// É o que torna o app gratuito de operar em escala: com lat/lng na base
  /// local, converter endereço em ponto no mapa vira uma consulta no SQLite —
  /// sem requisição, sem custo por usuário e funcionando offline. O centroide
  /// do CEP erra uns 100-200m em área urbana, o que não muda a **ordem** das
  /// paradas, que é o que o app decide.
  Future<void> _addCepCoordinates(Database db) async {
    // Colunas separadas do CREATE TABLE original porque bases antigas (v3) já
    // existem instaladas e só precisam ganhar as colunas.
    await db.execute('ALTER TABLE cep_directory ADD COLUMN latitude REAL');
    await db.execute('ALTER TABLE cep_directory ADD COLUMN longitude REAL');
  }

  /// Histórico do que já foi entregue.
  ///
  /// Antes, "limpar concluídas" apagava. O entregador perdia o registro do
  /// próprio dia de trabalho — quantas entregas fez, quanto rodou. Agora as
  /// concluídas saem da lista ativa e vão para cá.
  Future<void> _createHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE delivery_history (
        id               TEXT    PRIMARY KEY,
        label            TEXT,
        street           TEXT    NOT NULL,
        number           TEXT,
        complement       TEXT,
        neighborhood     TEXT,
        city             TEXT,
        state            TEXT,
        cep              TEXT,
        latitude         REAL,
        longitude        REAL,
        notes            TEXT,
        status           TEXT    NOT NULL,
        created_at       INTEGER NOT NULL,
        completed_at     INTEGER NOT NULL,
        distance_meters  REAL
      )
    ''');

    // A tela agrupa por dia, então o índice é pela data de conclusão.
    await db.execute(
      'CREATE INDEX idx_history_completed ON delivery_history(completed_at DESC)',
    );
  }

  /// A rota escolhida precisa sobreviver ao app ser fechado, morto pelo
  /// sistema ou ficar sem bateria no meio do dia. Sem isso o entregador perde
  /// a ordem e o progresso e tem que recomeçar — inaceitável no meio de um
  /// roteiro de 20 entregas.
  Future<void> _createActiveRouteTables(Database db) async {
    // Linha única: só existe uma rota em andamento por vez.
    await db.execute('''
      CREATE TABLE active_route (
        id                INTEGER PRIMARY KEY CHECK (id = 1),
        strategy          TEXT    NOT NULL,
        origin_latitude   REAL    NOT NULL,
        origin_longitude  REAL    NOT NULL,
        travel_seconds    REAL    NOT NULL,
        service_seconds   REAL    NOT NULL,
        distance_meters   REAL    NOT NULL,
        is_estimate       INTEGER NOT NULL,
        started_at        INTEGER NOT NULL
      )
    ''');

    // Os trechos guardam só o id da parada, não uma cópia dela. Assim editar
    // o endereço ou marcar como entregue reflete na rota sem sincronização
    // manual — e apagar a parada não deixa um trecho órfão.
    await db.execute('''
      CREATE TABLE active_route_legs (
        position          INTEGER PRIMARY KEY,
        stop_id           TEXT    NOT NULL,
        distance_meters   REAL    NOT NULL,
        duration_seconds  REAL    NOT NULL,
        FOREIGN KEY (stop_id) REFERENCES stops(id) ON DELETE CASCADE
      )
    ''');
  }

  /// Diretório local de CEP: o que faz o cadastro funcionar sem rede de
  /// verdade, e não só para endereços já vistos.
  ///
  /// Fica separado por UF porque a base do Brasil inteiro é grande demais para
  /// embarcar no APK. O usuário baixa só o estado em que trabalha — e
  /// entregador autônomo trabalha num estado só.
  Future<void> _createCepDirectoryTables(Database db) async {
    await db.execute('''
      CREATE TABLE cep_directory (
        cep            TEXT    PRIMARY KEY,
        street         TEXT,
        neighborhood   TEXT,
        city           TEXT    NOT NULL,
        state          TEXT    NOT NULL
      )
    ''');

    // A busca por cidade alimenta o autocomplete offline mais à frente.
    await db.execute(
      'CREATE INDEX idx_cep_directory_state_city ON cep_directory(state, city)',
    );

    // Controle de quais estados já foram importados, para a tela de bases
    // saber o que está instalado e quando.
    await db.execute('''
      CREATE TABLE cep_directory_packs (
        state          TEXT    PRIMARY KEY,
        entry_count    INTEGER NOT NULL,
        imported_at    INTEGER NOT NULL,
        source_version TEXT
      )
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
