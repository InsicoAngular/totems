// lib/services/database_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:mssql_connection/mssql_connection.dart';

import '../config/database_config.dart';
import '../models/municipality.dart';
import '../models/profile.dart';
import '../models/totem_info.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  final MssqlConnection _conn = MssqlConnection.getInstance();
  bool _initialized = false;

  String _sanitizeHost(String hostRaw) =>
      (hostRaw.trim().isEmpty ? '149.76.1.148' : hostRaw)
          .replaceFirst(RegExp(r'[\\/].*$'), '');

  Future<void> _ensureConnection() async {
    if (_initialized && _conn.isConnected) return;

    final host = _sanitizeHost(DatabaseConfig.ip);
    final portStr = DatabaseConfig.port.toString(); // mssql_connection usa String
    final db = (DatabaseConfig.dbName.trim().isEmpty)
        ? 'Puentealto_web_muni'
        : DatabaseConfig.dbName;
    final usr = (DatabaseConfig.user.trim().isEmpty)
        ? 'sa'
        : DatabaseConfig.user;
    final pwd = DatabaseConfig.pass;

    print('🔌 Intentando conectar a SQL Server');
    print('    Server: $host,$portStr');
    print('    Database: $db');
    print('    User: $usr');

    final ok = await _conn.connect(
      ip: host,
      port: portStr,
      databaseName: db,
      username: usr,
      password: pwd,
      timeoutInSeconds: 15,
      // Si tu SQL no tiene TLS configurado, podrías necesitar:
      // encrypt: false, trustServerCertificate: true,
    );
    if (!ok) {
      throw Exception(
          '❌ No se pudo conectar a SQL Server con $host,$portStr usando las credenciales proporcionadas.');
    }
    _initialized = true;
  }

  /*──────────────── HELPERS ────────────────*/

  // Obtiene int desde JSON tolerando mayúsculas/minúsculas en la llave.
  int _getInt(Map row, String key) {
    final v = row[key] ?? row[key.toLowerCase()] ?? row[key.toUpperCase()];
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  String _getStr(Map row, String key) {
    final v = row[key] ?? row[key.toLowerCase()] ?? row[key.toUpperCase()];
    return v?.toString() ?? '';
  }

  /*──────────────── MUNICIPALIDADES ─────────────────*/

  Future<List<Municipality>> fetchMunicipalities() async {
    await _ensureConnection();
    final js = await _conn.getData("""
      SELECT 
          m.MunicipalidadId       AS MunicipalidadId,
          m.NombreMuni            AS NombreMuni,
          COUNT(t.TotemId)        AS TotemCount
      FROM TO_Municipalidad m
      LEFT JOIN TO_Totems t ON t.MunicipalidadId = m.MunicipalidadId
      GROUP BY m.MunicipalidadId, m.NombreMuni
      ORDER BY m.NombreMuni;
    """);

    if (js == null || js.trim().isEmpty) {
      print('⚠️ fetchMunicipalities: respuesta vacía');
      return <Municipality>[];
    }
    print('📤 SQL municipalities: $js');

    final rows = (json.decode(js) as List).cast<Map>();
    return rows
        .map((r) => Municipality(
              id: _getInt(r, 'MunicipalidadId'),
              name: _getStr(r, 'NombreMuni'),
              totemCount: _getInt(r, 'TotemCount'),
            ))
        .toList();
  }

  /// Inserta municipalidad y retorna el ID. Con fallback por si el driver no devuelve el OUTPUT.
  Future<int> createMunicipality(String name) async {
    await _ensureConnection();

    // 1) Intento con OUTPUT + SELECT final (debería devolver filas siempre)
    final js1 = await _conn.getData("""
      SET XACT_ABORT ON;
      SET NOCOUNT ON;
      DECLARE @Ids TABLE (NewId INT);
      INSERT INTO TO_Municipalidad (NombreMuni)
        OUTPUT INSERTED.MunicipalidadId INTO @Ids(NewId)
      VALUES (N'${name.replaceAll("'", "''")}');
      SELECT NewId FROM @Ids;
    """);

    if (js1 != null && js1.trim().isNotEmpty) {
      final rows = (json.decode(js1) as List);
      if (rows.isNotEmpty) {
        final raw = rows.first is Map ? (rows.first as Map).values.first : rows.first;
        final id = (raw is num) ? raw.toInt() : int.tryParse(raw.toString()) ?? 0;
        if (id > 0) return id;
      }
      print('⚠️ createMunicipality: OUTPUT no trajo ID. json=$js1');
    } else {
      print('⚠️ createMunicipality: getData() vacío en primer intento');
    }

    // 2) Fallback: busca por nombre recién insertado (sirve si NombreMuni es UNIQUE)
    final js2 = await _conn.getData("""
      SELECT TOP 1 MunicipalidadId AS MunicipalidadId
      FROM TO_Municipalidad
      WHERE NombreMuni = N'${name.replaceAll("'", "''")}'
      ORDER BY MunicipalidadId DESC;
    """);
    if (js2 != null && js2.trim().isNotEmpty) {
      final rows = (json.decode(js2) as List).cast<Map>();
      if (rows.isNotEmpty) {
        final id = _getInt(rows.first, 'MunicipalidadId');
        if (id > 0) return id;
      }
    }

    throw Exception('createMunicipality: no se pudo obtener el ID insertado.');
  }

  Future<void> updateMunicipality({
    required int municipalidadId,
    required String newName,
  }) async {
    await _ensureConnection();
    await _conn.writeData("""
      UPDATE TO_Municipalidad
         SET NombreMuni = N'${newName.replaceAll("'", "''")}'
       WHERE MunicipalidadId = $municipalidadId;
    """);
  }

  Future<void> deleteMunicipality(int id) async {
    await _ensureConnection();
    await _conn.writeData(
      'DELETE FROM TO_Municipalidad WHERE MunicipalidadId=$id;',
    );
  }

  /*──────────────── PERFILES ─────────────────*/

  Future<List<Profile>> fetchProfiles() async {
    await _ensureConnection();
    final js = await _conn.getData(
      'SELECT PerfilId AS PerfilId, Codigo AS Codigo, Nombre AS Nombre FROM TO_Perfil ORDER BY Nombre;',
    );

    if (js == null || js.trim().isEmpty) return <Profile>[];
    print('📤 SQL profiles: $js');

    final rows = (json.decode(js) as List).cast<Map>();
    return rows
        .map((r) => Profile(
              id: _getInt(r, 'PerfilId'),
              code: _getStr(r, 'Codigo'),
              name: _getStr(r, 'Nombre'),
            ))
        .toList();
  }

  /*──────────────── TÓTEMS ─────────────────*/

  Future<int> createTotem({
    required int municipalidadId,
    required String nombre,
    required int perfilId,
  }) async {
    await _ensureConnection();

    final js1 = await _conn.getData("""
      SET XACT_ABORT ON;
      SET NOCOUNT ON;
      DECLARE @Ids TABLE (NewId INT);
      INSERT INTO TO_Totems (MunicipalidadId, Codigo, PerfilId)
        OUTPUT INSERTED.TotemId INTO @Ids(NewId)
      VALUES ($municipalidadId, N'${nombre.replaceAll("'", "''")}', $perfilId);
      SELECT NewId FROM @Ids;
    """);

    if (js1 != null && js1.trim().isNotEmpty) {
      final rows = (json.decode(js1) as List);
      if (rows.isNotEmpty) {
        final raw = rows.first is Map ? (rows.first as Map).values.first : rows.first;
        final id = (raw is num) ? raw.toInt() : int.tryParse(raw.toString()) ?? 0;
        if (id > 0) return id;
      }
      print('⚠️ createTotem: OUTPUT no trajo ID. json=$js1');
    }

    final js2 = await _conn.getData("""
      SELECT TOP 1 TotemId AS TotemId
      FROM TO_Totems
      WHERE MunicipalidadId = $municipalidadId AND Codigo = N'${nombre.replaceAll("'", "''")}'
      ORDER BY TotemId DESC;
    """);
    if (js2 != null && js2.trim().isNotEmpty) {
      final rows = (json.decode(js2) as List).cast<Map>();
      if (rows.isNotEmpty) {
        final id = _getInt(rows.first, 'TotemId');
        if (id > 0) return id;
      }
    }

    throw Exception('createTotem: no se pudo obtener el ID insertado.');
  }

  Future<List<TotemInfo>> fetchTotemsByMunicipality(int muniId) async {
    await _ensureConnection();
    final js = await _conn.getData("""
      SELECT 
          t.TotemId              AS TotemId, 
          t.Codigo               AS Codigo,
          m.MunicipalidadId      AS MunicipalidadId, 
          m.NombreMuni           AS NombreMuni,
          p.PerfilId             AS PerfilId, 
          p.Codigo               AS PerfilCod, 
          p.Nombre               AS PerfilNom
      FROM TO_Totems t
      JOIN TO_Municipalidad m ON m.MunicipalidadId = t.MunicipalidadId
      JOIN TO_Perfil       p ON p.PerfilId       = t.PerfilId
      WHERE t.MunicipalidadId = $muniId
      ORDER BY t.TotemId;
    """);

    if (js == null || js.trim().isEmpty) return <TotemInfo>[];
    print('📤 SQL totems: $js');

    final rows = (json.decode(js) as List).cast<Map>();
    return rows
        .map((r) => TotemInfo(
              totemId: _getInt(r, 'TotemId'),
              municipalidadId: _getInt(r, 'MunicipalidadId'),
              code: _getStr(r, 'Codigo'),
              nombreMuni: _getStr(r, 'NombreMuni'),
              profile: Profile(
                id: _getInt(r, 'PerfilId'),
                code: _getStr(r, 'PerfilCod'),
                name: _getStr(r, 'PerfilNom'),
              ),
            ))
        .toList();
  }

  /*──────────────── CONFIG ─────────────────*/

  Future<Map<String, dynamic>?> fetchConfig({required int totemId}) async {
    await _ensureConnection();
    final js = await _conn.getData(
      'SELECT ConfigJson AS ConfigJson, UpdatedAt AS UpdatedAt FROM TO_TotemConfig WHERE TotemId=$totemId;',
    );

    if (js == null || js.trim().isEmpty) return null;
    final rows = (json.decode(js) as List).cast<Map>();
    if (rows.isEmpty) return null;
    final r = rows.first;
    final rawDate = _getStr(r, 'UpdatedAt');
    DateTime? dt;
    try { dt = DateTime.parse(rawDate); } catch (_) {}
    return {'json': _getStr(r, 'ConfigJson'), 'updatedAt': dt};
  }

  Future<void> upsertConfig({
    required int totemId,
    required String configJson,
  }) async {
    await _ensureConnection();
    await _conn.writeData("""
      MERGE TO_TotemConfig AS t
      USING (VALUES ($totemId)) AS s(TotemId)
        ON t.TotemId = s.TotemId
      WHEN MATCHED THEN
        UPDATE SET ConfigJson = N'${configJson.replaceAll("'", "''")}', UpdatedAt = GETDATE()
      WHEN NOT MATCHED THEN
        INSERT (TotemId, ConfigJson) VALUES ($totemId, N'${configJson.replaceAll("'", "''")}');
    """);
  }

  /*──────────────── DIAGNÓSTICO ────────────────*/

  Future<String> diag() async {
    await _ensureConnection();
    final js = await _conn.getData("""
      SELECT
        DB_NAME()     AS Db,
        @@SERVERNAME  AS ServerName,
        SUSER_SNAME() AS LoginName,
        GETDATE()     AS Now;
      SELECT COUNT(*) AS MuniCount FROM TO_Municipalidad;
      SELECT TOP 5 MunicipalidadId, NombreMuni FROM TO_Municipalidad ORDER BY MunicipalidadId DESC;
    """);
    return js ?? '<vacío>';
  }
}
