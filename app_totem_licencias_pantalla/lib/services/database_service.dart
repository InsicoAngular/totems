// lib/services/database_service.dart
import 'dart:convert';
import 'package:mssql_connection/mssql_connection.dart';
import '../models/ticket.dart';
import '../config/database_config.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  final MssqlConnection _conn = MssqlConnection.getInstance();
  bool _initialized = false;

  // Credenciales inyectadas con --dart-define
  final String _ip     = DatabaseConfig.ip;
  final String _port   = DatabaseConfig.port;
  final String _dbName = DatabaseConfig.dbName;
  final String _user   = DatabaseConfig.user;
  final String _pass   = DatabaseConfig.pass;

  /*───────────────────────── Conexión ─────────────────────────*/
  Future<void> _ensureConnection() async {
    DatabaseConfig.validate();

    if (_initialized) return;

    final ok = await _conn.connect(
      ip: _ip,
      port: _port,
      databaseName: _dbName,
      username: _user,
      password: _pass,
      timeoutInSeconds: 15,
    );

    if (!ok) throw Exception('No se pudo conectar a SQL Server');
    _initialized = true;
  }

  /*───────────── Configuración del tótem ─────────────*/
  Future<String?> fetchConfigJson() async {
    final id = DatabaseConfig.totemId;
    if (id <= 0) return null;

    await _ensureConnection();

    final js = await _conn.getData('''
      SELECT ConfigJson
        FROM TO_TotemConfig
       WHERE TotemId = $id;
    ''');

    final rows = json.decode(js) as List;
    if (rows.isEmpty) return null;

    return (rows.first as Map<String, dynamic>)['ConfigJson'] as String?;
  }

  /*─────────────── DEBUG rápido de fechas ───────────────*/
  Future<void> debugFechasEnTabla() async {
    await _ensureConnection();

    final sql = '''
      SELECT DISTINCT TOP 10
             t.fecha,
             STUFF(STUFF(t.fecha,7,0,'-'),5,0,'-') AS fecha_formatted,
             COUNT(*) AS cantidad
        FROM ALCLLAMADOSTOTEM t
       WHERE t.fecha = CONVERT(char(8), GETDATE(), 112)
    GROUP BY t.fecha
    ORDER BY t.fecha DESC;
    ''';

    try {
      final jsonResult = await _conn.getData(sql);
      final List rows = json.decode(jsonResult);

      print('🔍 FECHAS EN ALCLLAMADOSTOTEM');
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        print('   ${row['fecha']}  |  ${row['fecha_formatted']}  |  ${row['cantidad']} filas');
      }
    } catch (e) {
      print('❌ Error debug fechas: $e');
    }
  }

  /*─────────── Últimos 3 llamados ÚNICOS del día ───────────*/
Future<List<Ticket>> fetchTicketsHoy() async {
  await _ensureConnection();

  final sql = '''
SELECT TOP 3
       t.id,
       l.NombreCompleto         AS nombre,
       LTRIM(RTRIM(t.modulo))   AS modulo,
       t.EsManual               AS EsManual,
       l.Tipo_Espera            AS tipoEspera
FROM  dbo.ALCLLAMADOSTOTEM t
JOIN  dbo.ALCLLAMADOS      l ON l.id = t.id_llamados
WHERE t.fecha = CONVERT(char(8), GETDATE(), 112)
ORDER BY t.id DESC;
''';

  final jsonResult = await _conn.getData(sql);
  final List rows = json.decode(jsonResult);

  final tickets = <Ticket>[];
  for (final raw in rows) {
    final row = Map<String, dynamic>.from(raw);
    tickets.add(Ticket(
      id: int.tryParse('${row['id']}') ?? 0,
      name: (row['nombre'] ?? '').toString(),
      station: (row['modulo'] ?? '').toString(),        // ← ojo: usa "modulo"
      isManual: row['EsManual'] == true || row['EsManual'] == 1,
      tipoEspera: (row['tipoEspera'] ?? '').toString(),
    ));
  }
  return tickets;
}

  /*────── Consulta sin JOIN (solo para debug visual) ──────*/
  Future<List<Ticket>> fetchTicketsHoySimple() async {
    await _ensureConnection();

    final sql = '''
      SELECT TOP 10
             id_llamado AS id,
             modulo,
             fecha,
             STUFF(STUFF(fecha,7,0,'-'),5,0,'-') AS fecha_formatted
        FROM ALCLLAMADOSTOTEM
       WHERE fecha = CONVERT(char(8), GETDATE(), 112)
         AND id_llamado IS NOT NULL
    ORDER BY id_llamado DESC;
    ''';

    final jsonResult = await _conn.getData(sql);
    final rows = json.decode(jsonResult) as List;
    print('🔍 Simple (sin JOIN): ${rows.length} filas');
    return [];
  }
}
