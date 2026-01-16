// lib/services/database_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_totem_licencias/models/atencion.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mssql_connection/mssql_connection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/database_config.dart';
import '../models/insert_result.dart';
import '../models/practico_result.dart';
import '../models/reserva.dart';

/// ===== Helpers como extensions (TOP-LEVEL, fuera de clases) =====
extension _NumX on num? {
  int get asInt => (this ?? 0).toInt();
}

extension _StrX on Object? {
  String get asStr => (this ?? '').toString();
}

// ---- Pon esto cerca de tus models (mismo archivo o uno aparte) ----
class EndpointResult {
  final bool ok;
  final int status; // HTTP status (o -1/-2 errores locales)
  final String? message; // mensaje “bonito” si se pudo parsear
  final String? body; // body crudo

  const EndpointResult({
    required this.ok,
    required this.status,
    this.message,
    this.body,
  });
}

/// ───────── Verificación de cupos manuales (TOP-LEVEL) ─────────
class CupoCheck {
  final bool ok;
  final int? cupoId;
  final int disponibles;
  final String motivo;
  final String horaInicio; // "08:30:00"
  final String horaTermino; // "17:04:00"
  final bool dentroHorario;

  const CupoCheck({
    required this.ok,
    this.cupoId,
    required this.disponibles,
    required this.motivo,
    required this.horaInicio,
    required this.horaTermino,
    required this.dentroHorario,
  });
}

class PracticoFlowResult {
  final bool ok;
  final int? ticket;
  final String? nombre;
  final List<Map<String, dynamic>> etapas;
  final String? message;

  PracticoFlowResult({
    required this.ok,
    this.ticket,
    this.nombre,
    this.etapas = const [],
    this.message,
  });
}

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  /* ───────── conexión ───────── */
  final _conn = MssqlConnection.getInstance();
  bool _initialized = false;

  final _ip = DatabaseConfig.ip;
  final _port = DatabaseConfig.port;
  final _db = DatabaseConfig.dbName;
  final _usr = DatabaseConfig.user;
  final _pwd = DatabaseConfig.pass;
  final _endpoint = DatabaseConfig.endpoint;
  final _totemId = DatabaseConfig.totemId;

  // ───────── helpers extra ─────────
  String _onlyDigits(String s) => s.replaceAll(RegExp(r'\D'), '');
  bool get _isPractico => DatabaseConfig.practico;
  int? _profileId;

  /* ───────── helpers ───────── */
  String _toAnsi(String t) => t;

  String _normalize(String s) {
    var out = s.toLowerCase().trim();
    const f = 'áéíóúñ', t = 'aeioun';
    for (var i = 0; i < f.length; i++) {
      out = out.replaceAll(f[i], t[i]);
    }
    return out;
  }

  String _escapeSqlUnicode(String s) => s.replaceAll("'", "''");

  /* ───────── conexión + perfil ───────── */
  Future<void> _ensureConnection() async {
    if (_initialized) return;

    final ok = await _conn.connect(
      ip: _ip,
      port: _port,
      databaseName: _db,
      username: _usr,
      password: _pwd,
      timeoutInSeconds: 15,
    );
    if (!ok) throw Exception('No se pudo conectar a SQL Server');

    final js = await _conn.getData(
      'SELECT PerfilId FROM TO_Totems WHERE TotemId=$_totemId',
    );
    final rows = jsonDecode(js) as List;
    if (rows.isEmpty) {
      throw Exception('TotemId $_totemId no existe en la BD');
    }
    _profileId = rows.first['PerfilId'] as int;
    _initialized = true;
  }

  /* ───────── config remota ───────── */
  Future<String?> fetchConfigJson() async {
    await _ensureConnection();
    if (_totemId == 0) return null;

    final js = await _conn.getData(
      'SELECT ConfigJson FROM TO_TotemConfig WHERE TotemId=$_totemId',
    );
    final rows = jsonDecode(js) as List;
    return rows.isEmpty ? null : rows.first['ConfigJson'] as String;
  }

  /* ────────── FETCH RESERVA / PRÁCTICO ────────── */
  Future<dynamic /* Reserva? | PracticoResult? */> fetchReserva(
    String rut,
  ) async {
    await _ensureConnection();
    switch (_profileId) {
      case 1:
        return _isPractico
            ? _fetchEstadoPractico(rut)
            : _fetchReservaLicencias(rut);
      default:
        throw UnsupportedError('Perfil $_profileId aún no implementado');
    }
  }

  /*──────────────────── LICENCIAS · lee reserva del endpoint ───────────────────*/
  Future<Reserva?> _fetchReservaLicencias(String rut) async {
    debugPrint('[LICENCIAS] llamando API para $rut');

    final url = '$_endpoint/api/conector/v1/reservaTOTEM/$rut';
    debugPrint('[LICENCIAS] URL completa: $url');
    debugPrint('[LICENCIAS] Endpoint base: $_endpoint');

    http.Response resp;
    try {
      // Headers para evitar caché y forzar conexión fresca
      resp = await http
          .get(
            Uri.parse(url),
            headers: {
              'Cache-Control': 'no-cache, no-store, must-revalidate',
              'Pragma': 'no-cache',
              'Expires': '0',
              'Accept': 'application/json',
            },
          )
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              debugPrint('[LICENCIAS] Timeout después de 20 segundos');
              throw TimeoutException('La solicitud tardó más de 20 segundos');
            },
          );
    } on TimeoutException catch (e) {
      debugPrint('[LICENCIAS] Timeout: $e');
      throw Exception(
        'Timeout: El servidor no respondió a tiempo. Verifica tu conexión a internet.',
      );
    } on SocketException catch (e) {
      debugPrint('[LICENCIAS] Error de socket: $e');
      throw Exception(
        'Error de conexión: No se pudo conectar al servidor. Verifica tu conexión a internet y que el servidor esté disponible.',
      );
    } on HttpException catch (e) {
      debugPrint('[LICENCIAS] Error HTTP: $e');
      throw Exception('Error HTTP: $e');
    } catch (e) {
      debugPrint('[LICENCIAS] Error desconocido: $e');
      debugPrint('[LICENCIAS] Tipo de error: ${e.runtimeType}');
      throw Exception('Error de conexión: ${e.toString()}');
    }

    debugPrint('[LICENCIAS] HTTP ${resp.statusCode}');
    if (resp.statusCode != 200) {
      debugPrint('[LICENCIAS] Status code no es 200: ${resp.statusCode}');
      debugPrint('[LICENCIAS] Body: ${resp.body}');
      return null;
    }

    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      debugPrint('[LICENCIAS] body: $body');

      if (body['success'] != true) {
        debugPrint('[LICENCIAS] body["success"] != true');
        return null;
      }

      final data = body['data'] as List;
      debugPrint('[LICENCIAS] data.length = ${data.length}');
      if (data.isEmpty) return null;

      final reserva = Reserva.fromJson(Map<String, dynamic>.from(data.first));
      debugPrint(
        '[LICENCIAS] Reserva OK fecha=${reserva.fechaCitacion} hora=${reserva.horaCitacion}',
      );
      return reserva;
    } catch (e) {
      debugPrint('[LICENCIAS] Error parseando respuesta: $e');
      debugPrint('[LICENCIAS] Body recibido: ${resp.body}');
      throw Exception(
        'Error al procesar respuesta del servidor: ${e.toString()}',
      );
    }
  }

  Future<PracticoResult?> _fetchEstadoPractico(String rut) async {
    final cleaned = rut.replaceAll('.', '').trim();
    final parts = cleaned.split('-');
    if (parts.length != 2) return null;

    final numero = int.tryParse(parts[0]) ?? 0;
    final digito = parts[1].toUpperCase();

    final sql = '''
SELECT TOP 1
  pa.PAPersonaId,
  pa.RutNumero,
  pa.RutDigito,
  CONCAT(pa.Nombres,' ',pa.ApellidoPaterno,' ',pa.ApellidoMaterno) AS nombre,
  af.FechaResultado,
  ae.ALCParametro_General_Etapa_id,
  af.ALCEstado_id,
  af.Resultado,
  am.FechaSolicitud,
  pra_last.L09_OPORTU,
  pra_last.L09_RESULT,
  clp.Nombre AS clase
FROM PAPersona pa
JOIN ALCMaestro             am   ON pa.PAPersonaId = am.PAPersonaId
JOIN ALCEstados             ae   ON am.id          = ae.ALCMaestro_id
JOIN ALCEstados_Flujos      af   ON ae.id          = af.ALCEstado_id
OUTER APPLY (
  SELECT TOP 1 p.*
  FROM ALCExapra p
  WHERE p.ALCMaestro_id = am.id
  ORDER BY p.id DESC              -- o p.Fecha si prefieres
) pra_last
JOIN ALCClases             clas ON clas.ALCMaestro_id = am.id
JOIN ALCParametros_Clases  clp  ON clp.id = clas.ALCParametros_Clase_id
WHERE pa.RutNumero = $numero
  AND pa.RutDigito COLLATE SQL_Latin1_General_CP1_CI_AI = '$digito'
  AND am.L01_ESTADO LIKE '%SOL%'
  AND ae.ALCParametro_General_Etapa_id >= 886
  AND (pra_last.ALCMaestro_id IS NULL OR pra_last.L09_RESULT <> 'R') 
ORDER BY am.ID DESC, af.FechaResultado DESC, COALESCE(pra_last.id, 0) DESC;    
    ''';

    final js = await _conn.getData(sql);
    final rows = jsonDecode(js) as List;
    return rows.isEmpty
        ? null
        : PracticoResult.fromJson(Map<String, dynamic>.from(rows.first));
  }

  /*──────── MAIN fetchAndInsert ───────*/
  Future<InsertResult> fetchAndInsert(String rut, String code) async {
    await _ensureConnection();

    if (_isPractico) {
      return _fetchAndInsertPractico(rut);
    }

    if (code == 'ON') {
      try {
        final reserva = await _fetchReservaLicencias(rut);
        if (reserva == null) {
          return InsertResult(
            success: false,
            message: 'No se encontró reserva activa',
          );
        }
        return _insertAtencionLicencias(reserva);
      } catch (e) {
        return InsertResult(success: false, message: e.toString());
      }
    }

    return registrarDesdeALC(rut: rut, tipo: code);
  }

  /* ─────────────── LICENCIAS - INSERT EN ALCATENCIONES (vía SP) ─────────────── */
  Future<InsertResult> _insertAtencionLicencias(Reserva r) async {
    await _ensureConnection();

    try {
      // 1) Mapea clase → tipo interno (si igual necesitas este valor lo dejamos)
      final claseNorm = _normalize(r.clase2);
      final tipoLocal = DatabaseConfig.tramiteMap[claseNorm] ?? 'P';

      // 2) Parseo de fecha/hora que vienen del endpoint
      //    Ajusta si tu API ya trae un ISO completo; aquí asumimos fecha "YYYY-MM-DD" y hora "HH:mm".
      final String f = (r.fechaCitacion ?? '').trim();
      final String h = (r.horaCitacion ?? '').trim();
      final DateTime dt = DateTime.parse('$f $h');

      //   Formatos que pide el SP:
      //   - Fecha CHAR(8) → "YYYYMMDD"
      //   - Hora  CHAR(5) → "HH:MM"
      String two(int n) => n.toString().padLeft(2, '0');
      final fechaExt = '${dt.year}${two(dt.month)}${two(dt.day)}'; // YYYYMMDD
      final horaExt = '${two(dt.hour)}:${two(dt.minute)}'; // HH:MM

      // 3) Llama al SP **con Tipo='I'** (Internet) y pasando fecha/hora del endpoint
      final rutDb = _rutConcatConDvStrict(r.numRut);
      if (rutDb.isEmpty) {
        return InsertResult(success: false, message: 'RUT inválido (falta DV)');
      }

      final nombresDb = _foldForDb(r.nombres);
      final apellidosDb = _foldForDb(r.apellidos);

      final sql = """
EXEC dbo.sp_ALC_InsertAtencion_TipoDia
  @NumRut     = '$rutDb',
  @Tipo       = 'I',                         -- ✅ Solicitud Internet
  @Nombres    = N'$nombresDb',
  @Apellidos  = N'$apellidosDb',
  @UsuarioMod = N'TOTEM',
  @IPLocal    = N'0.0.0.0',
  @FechaExt   = '$fechaExt',                 -- ✅ 'YYYYMMDD'
  @HoraExt    = '$horaExt';                  -- ✅ 'HH:MM'
""";

      final rows = List<Map<String, dynamic>>.from(
        jsonDecode(await _conn.getData(sql)),
      );
      if (rows.isEmpty) {
        return InsertResult(success: false, message: 'Sin respuesta del SP');
      }

      final r0 = rows.first;
      final ticketDia = (r0['Ticket'] as num?)?.toInt() ?? 0;
      final idAtencion = (r0['IdAtencion'] as num?)?.toInt() ?? 0;

      if (ticketDia <= 0 || idAtencion <= 0) {
        return InsertResult(
          success: false,
          message: 'No se pudo generar correlativo',
        );
      }

      // 4) (OPCIONAL) Alinear correlativo corto visible en otras vistas (si corresponde en tu instalación)
      try {
        await _conn.writeData("""
        UPDATE ALCAtenciones
           SET L28_CORRELATIVO = $ticketDia
         WHERE id = $idAtencion;
      """);
      } catch (_) {}

      // 5) Opcional: generar/actualizar numsol local (si tu flujo lo usa)
      final rutSolo = _onlyDigits(r.numRut);
      final filtroRut =
          (rutDb.isNotEmpty)
              ? "L28_NUMRUT IN ('$rutDb', '$rutSolo')"
              : "L28_NUMRUT = '$rutSolo'";

      final calcJs = await _conn.getData("""
      DECLARE @FECHA CHAR(8) = CONVERT(CHAR(8), GETDATE(), 112);
      SELECT MAX(TRY_CAST(L28_NUMSOL AS INT)) AS max_sol
        FROM ALCAtenciones
       WHERE L28_FECHA = @FECHA
         AND $filtroRut
         AND L28_TIPO   = 'I';
    """);
      final arr = jsonDecode(calcJs) as List;
      final row =
          arr.isEmpty ? <String, dynamic>{} : arr.first as Map<String, dynamic>;
      final maxSol = (row['max_sol'] ?? 0) as int;
      final nextNumSol = (maxSol + 1).toString();

      await _conn.writeData("""
      UPDATE ALCAtenciones
         SET L28_NUMSOL = '$nextNumSol'
       WHERE id = $idAtencion;
    """);

      return InsertResult(
        success: true,
        ticket: ticketDia,
        message: 'Registro exitoso (Solicitud Internet)',
        extra: {'id': idAtencion, 'numSol': nextNumSol, 'tipoLocal': tipoLocal},
      );
    } catch (e) {
      return InsertResult(success: false, message: 'Error BD: $e');
    }
  }

  /* ─────────────── PRÁCTICO ─────────────── */
  Future<List<Map<String, dynamic>>> _fetchEtapas(int estadoId) async {
    final js = await _conn.getData("""
      SELECT
        pa.RutNumero,
        pa.RutDigito,
        CONCAT(pa.Nombres, ' ', pa.ApellidoPaterno, ' ', pa.ApellidoMaterno) AS Nombre,
        af.ALCParametros_General_Etapa_id AS EtapaId,
        af.Resultado,
        CASE WHEN af.Resultado IN ('E','S') THEN 1 ELSE 0 END AS Pendiente
      FROM PAPersona             pa
      JOIN ALCMaestro            al ON pa.PAPersonaId = al.PAPersonaId
      JOIN ALCEstados            ae ON al.id          = ae.ALCMaestro_id
      JOIN ALCEstados_Flujos     af ON ae.id         = af.ALCEstado_id
      WHERE af.ALCEstado_id = $estadoId
        AND af.ALCParametros_General_Etapa_id BETWEEN 880 AND 889
      ORDER BY af.ALCParametros_General_Etapa_id;
    """);

    final rows = List<Map<String, dynamic>>.from(jsonDecode(js));
    return rows;
  }

  Future<InsertResult> registrarPracticoEnALCAtenciones(
    String rut, {
    String nombres = '',
    String apellidos = '',
  }) async {
    return _fetchAndInsertPractico(rut);
  }

  Future<InsertResult> _fetchAndInsertPractico(String rut) async {
    final res = await _fetchEstadoPractico(rut);
    if (res == null) return InsertResult(success: false);

    final etapas = await _fetchEtapas(res.estadoId);
    final pendiente = etapas.any(
      (e) =>
          e['EtapaId'] <= 885 &&
          (e['Resultado'] == 'E' || e['Resultado'] == 'S'),
    );

    if (pendiente) {
      return InsertResult(success: false, extra: etapas);
    }

    return insertarAtencionTipoDia(
      rut: rut,
      tipo: 'T',
      nombres: res.nombre,
      apellidos: '',
    );
  }

  /* ─────────── refresco local config ─────────── */
  Future<bool> refreshLocalConfig() async {
    final raw = await fetchConfigJson();
    if (raw == null) return false;

    late final Map<String, dynamic> cfg;
    try {
      cfg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs
      ..setString('welcomeText', cfg['welcomeText'] ?? '')
      ..setString('hashtag', cfg['hashtag'] ?? '')
      ..setString('marqueeText', cfg['marqueeText'] ?? '')
      ..setInt('buttonBg', cfg['buttonBg'] ?? Colors.deepPurple.value)
      ..setInt('buttonText', cfg['buttonText'] ?? Colors.white.value)
      ..setString('assetsDir', cfg['assetsDir'] ?? r'C:\Insico\assets\');
    return true;
  }

  /// Consume cupo manual del día y retorna el correlativo asignado.
  Future<InsertResult> consumirManual() async {
    await _ensureConnection();

    final sql = """
DECLARE @c int, @m nvarchar(200), @rc int;
EXEC @rc = dbo.sp_TO_Manual_Consume
          @TotemId=$_totemId,
          @Correlativo=@c OUTPUT,
          @Msg=@m OUTPUT;
SELECT rc=@rc, correlativo=@c, msg=@m;
""";

    final rows = List<Map<String, dynamic>>.from(
      jsonDecode(await _conn.getData(sql)),
    );
    if (rows.isEmpty) {
      return InsertResult(
        success: false,
        message: 'Sin respuesta del servidor',
      );
    }
    final r = rows.first;
    final ok = (r['rc'] as int?) == 0;
    final num = (r['correlativo'] as int?) ?? 0;
    final msg = (r['msg'] as String?) ?? (ok ? 'OK' : 'Error');

    return InsertResult(success: ok, ticket: num, message: msg);
  }

  /* ───────── ALC (lectura/confirmación) ───────── */
  Future<Atencion?> _fetchAtencionALC(String rut, String tipo) async {
    await _ensureConnection();

    final rutSolo = _onlyDigits(rut);
    final rutDb = _rutConcatConDvStrict(rut);
    final tipoAnsi = _toAnsi(tipo).replaceAll("'", "''");

    final filtroRut =
        (rutDb.isNotEmpty)
            ? "a.L28_NUMRUT IN ('$rutDb', '$rutSolo')"
            : "a.L28_NUMRUT = '$rutSolo'";

    final sql = """
DECLARE @FECHA CHAR(8) = CONVERT(CHAR(8), GETDATE(), 112);
;WITH CANDIDATOS AS (
    SELECT a.*, 1 AS prio
      FROM ALCAtenciones a
     WHERE a.L28_FECHA = @FECHA
       AND $filtroRut
       AND a.L28_TIPO   = '$tipoAnsi'
       AND (a.L28_ATENDIDO IS NULL OR a.L28_ATENDIDO='N')
       AND a.L28_ASIGNADO='S'

    UNION ALL
    SELECT a.*, 2 AS prio
      FROM ALCAtenciones a
     WHERE a.L28_FECHA = @FECHA
       AND $filtroRut
       AND a.L28_TIPO   = '$tipoAnsi'
       AND (a.L28_ATENDIDO IS NULL OR a.L28_ATENDIDO='N')

    UNION ALL
    SELECT a.*, 3 AS prio
      FROM ALCAtenciones a
     WHERE a.L28_FECHA = @FECHA
       AND $filtroRut
       AND (a.L28_ATENDIDO IS NULL OR a.L28_ATENDIDO='N')
       AND a.L28_ASIGNADO='S'

    UNION ALL
    SELECT a.*, 4 AS prio
      FROM ALCAtenciones a
     WHERE a.L28_FECHA = @FECHA
       AND $filtroRut
       AND (a.L28_ATENDIDO IS NULL OR a.L28_ATENDIDO='N')
)
SELECT TOP 1 *
  FROM CANDIDATOS
 ORDER BY prio ASC, id DESC;
""";

    final js = await _conn.getData(sql);
    final rows = List<Map<String, dynamic>>.from(jsonDecode(js));
    if (rows.isEmpty) return null;
    return Atencion.fromJson(rows.first);
  }

  Future<bool> _touchALC(int id) async {
    await _ensureConnection();

    final now = DateTime.now();
    final fecha =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final hora = _fmtHms(now);

    final sql = """
UPDATE ALCAtenciones
   SET L28_HORA      = ISNULL(L28_HORA, '$hora'),
       intentos      = ISNULL(intentos,0) + 1,
       L28_USUARIO_MOD='TOTEM',
       L28_FECHA_MOD='$fecha',
       L28_HORA_MOD ='$hora'
 WHERE id=$id;
""";

    try {
      await _conn.writeData(sql);
      return true;
    } catch (_) {
      return false;
    }
  }

  int _asInt(String? s) => int.tryParse((s ?? '').trim()) ?? 0;

  int _bestTicketFromAtencion(Atencion a) {
    final c1 = _asInt(a.correlativo1);
    if (c1 > 0) return c1;
    final c0 = _asInt(a.correlativo);
    if (c0 > 0) return c0;
    final sol = _asInt(a.numSol);
    if (sol > 0) return sol;
    return a.id;
  }

  Future<InsertResult> registrarDesdeALC({
    required String rut,
    required String tipo,
  }) async {
    await _ensureConnection();

    final a = await _fetchAtencionALC(rut, tipo);
    if (a == null) {
      return InsertResult(
        success: false,
        message: 'No hay atención registrada para hoy con ese trámite',
      );
    }

    final ok = await _touchALC(a.id);
    final ticketOk = _bestTicketFromAtencion(a);
    return InsertResult(
      success: ok,
      ticket: ticketOk,
      message:
          ok
              ? 'Atención confirmada, imprimiendo voucher'
              : 'No se pudo confirmar la atención',
      extra: {
        'id': a.id,
        'fecha': a.fecha,
        'tipo': a.tipo,
        'numRut': a.numRut,
        'nombres': a.nombres ?? '',
        'apellidos': a.apellidos ?? '',
        'numSol': a.numSol ?? '',
        'correlativo': a.correlativo,
        'correlativo1': a.correlativo1 ?? '',
      },
    );
  }

  /* ───────── Cupos / Botones manuales ───────── */
  Future<CupoCheck> checkCupoPracticoCombinado() async {
    return _checkCupoUnionPorLabels(
      labels: const ['Examenes Practicos', 'Examenes Practicos C y CR'],
      requiereApertura: false,
    );
  }

  Future<CupoCheck> checkCupoManualPorLabel({
    required String labelTramite,
    bool requiereApertura = true,
  }) async {
    await _ensureConnection();

    final alias =
        DatabaseConfig.tramitesByLabel(
          labelTramite,
        ).map((e) => _toAnsi(e).replaceAll("'", "''")).toList();
    final inList = alias.map((a) => "N'$a'").join(',');

    final reqApertura =
        DatabaseConfig.isPracticoLabel(labelTramite) ? false : requiereApertura;

    final sql = """
;WITH bloques AS (
  SELECT
    id, tramite, horaInicio, horaTermino, cantidad,
    CAST(CASE WHEN ISNULL(activo,0)=1 THEN 1 ELSE 0 END AS bit) AS activo,
    ISNULL(cuposUsados, 0) AS cuposUsados,
    jornada,
    CASE
      WHEN CONVERT(time, GETDATE()) BETWEEN horaInicio AND horaTermino THEN 0
      WHEN horaInicio > CONVERT(time, GETDATE()) THEN 1
      ELSE 2
    END AS rankSel,
    CASE WHEN CONVERT(time, GETDATE()) BETWEEN horaInicio AND horaTermino THEN 1 ELSE 0 END AS dentroHorario
  FROM ALCBotonesTotem WITH (READPAST)
  WHERE ISNULL(activo,0)=1
    AND (
      tramite COLLATE SQL_Latin1_General_CP1_CI_AI IN ($inList)
      OR tramite COLLATE SQL_Latin1_General_CP1_CI_AI LIKE
         N'%' + LOWER(N'${_toAnsi(labelTramite).replaceAll("'", "''")}') + N'%'
    )
)
SELECT TOP 1
  id, tramite,
  CONVERT(varchar(8), horaInicio, 108)  AS horaInicio,
  CONVERT(varchar(8), horaTermino, 108) AS horaTermino,
  cantidad, activo, cuposUsados, jornada, dentroHorario,
  (cantidad - cuposUsados) AS stock
FROM bloques
ORDER BY
  rankSel ASC,                                            -- 0: dentro, 1: futuro, 2: pasado
  CASE WHEN (cantidad - cuposUsados) > 0 THEN 0 ELSE 1 END ASC,  -- stock primero
  CASE WHEN rankSel=0 AND jornada='T' THEN 0 ELSE 1 END ASC,
  CASE WHEN rankSel=0 THEN horaInicio END DESC,
  CASE WHEN rankSel=1 THEN horaInicio END ASC,
  horaInicio DESC,
  id ASC; -- desempate estable
""";

    final rows = List<Map<String, dynamic>>.from(
      jsonDecode(await _conn.getData(sql)),
    );
    if (rows.isEmpty) {
      return const CupoCheck(
        ok: false,
        cupoId: null,
        disponibles: 0,
        motivo: 'No se han habilitado cupos para este trámite',
        horaInicio: '00:00:00',
        horaTermino: '00:00:00',
        dentroHorario: false,
      );
    }

    final r = rows.first;
    final id = (r['id'] as num).toInt();
    final stock = (r['stock'] as num).toInt();
    final usados = (r['cuposUsados'] as num).toInt();
    final dentro = (r['dentroHorario'] as num).toInt() == 1;
    final hIni = r['horaInicio'].toString();
    final hFin = r['horaTermino'].toString();

    final abiertos = !reqApertura || usados >= 1;
    if (!abiertos) {
      return CupoCheck(
        ok: false,
        cupoId: id,
        disponibles: stock,
        motivo: 'No se han habilitado cupos para este trámite',
        horaInicio: hIni,
        horaTermino: hFin,
        dentroHorario: dentro,
      );
    }
    if (!dentro) {
      return CupoCheck(
        ok: false,
        cupoId: id,
        disponibles: stock,
        motivo: 'Fuera de horario',
        horaInicio: hIni,
        horaTermino: hFin,
        dentroHorario: dentro,
      );
    }
    if (stock <= 0) {
      return const CupoCheck(
        ok: false,
        cupoId: null,
        disponibles: 0,
        motivo: 'Cupos agotados por hoy',
        horaInicio: '00:00:00',
        horaTermino: '00:00:00',
        dentroHorario: true,
      );
    }

    return CupoCheck(
      ok: true,
      cupoId: id,
      disponibles: stock,
      motivo: 'OK',
      horaInicio: hIni,
      horaTermino: hFin,
      dentroHorario: dentro,
    );
  }

  Future<int> ensurePracticoTicket({
    required String rut,
    String? nombres,
    String? apellidos,
  }) async {
    final res = await insertarAtencionTipoDia(
      rut: rut,
      tipo: 'T',
      nombres: nombres ?? '',
      apellidos: apellidos ?? '',
    );
    return res.ticket ?? 0;
  }

  Future<InsertResult> insertarAtencionTipoDia({
    required String rut,
    String tipo = 'T',
    String nombres = '',
    String apellidos = '',
    String usuario = 'TOTEM',
    String ipLocal = '0.0.0.0',
  }) async {
    await _ensureConnection();

    // ✅ RUT con DV (NNNNNNNNDV, acepta K)
    final rutDb = _rutConcatConDvStrict(rut);
    if (rutDb.isEmpty) {
      return InsertResult(success: false, message: 'RUT inválido (falta DV)');
    }

    // 👇 Plegamos SOLO para BD (la tabla es VARCHAR / no UTF-8)
    final nombresDb = _foldForDb(nombres);
    final apellidosDb = _foldForDb(apellidos);
    final tipoSql = _foldForDb(tipo);
    final usuarioSql = _foldForDb(usuario);
    final ipSql = _foldForDb(ipLocal);

    final sql = """
EXEC dbo.sp_ALC_InsertAtencion_TipoDia
  @NumRut     = '$rutDb',
  @Tipo       = N'$tipoSql',
  @Nombres    = N'$nombresDb',
  @Apellidos  = N'$apellidosDb',
  @UsuarioMod = N'$usuarioSql',
  @IPLocal    = N'$ipSql';
""";

    final js = await _conn.getData(sql);
    final rows = List<Map<String, dynamic>>.from(jsonDecode(js));
    if (rows.isEmpty) {
      return InsertResult(success: false, message: 'Sin respuesta del SP');
    }
    final r = rows.first;
    final ticket = (r['Ticket'] as num?)?.toInt() ?? 0;
    final id = (r['IdAtencion'] as num?)?.toInt() ?? 0;

    return InsertResult(
      success: ticket > 0,
      ticket: ticket,
      message:
          ticket > 0 ? 'Atención registrada' : 'No se pudo generar correlativo',
      extra: {'id': id, 'Fecha': r['Fecha'], 'Tipo': r['Tipo']},
    );
  }

  String _rutConcatConDvStrict(String rut) {
    final clean = rut.replaceAll(RegExp(r'[^0-9kK]'), '').toUpperCase();
    if (clean.length < 8) return ''; // 👈 exige DV
    if (!RegExp(r'^\d{7,8}[0-9K]$').hasMatch(clean)) return '';
    return clean;
  }

  Map<String, dynamic> _splitRut(String rut) {
    final clean = rut.replaceAll('.', '').replaceAll('-', '');
    if (clean.length < 2) return {'num': 0, 'dv': ''};
    final dv = clean.substring(clean.length - 1).toUpperCase();
    final num = int.tryParse(clean.substring(0, clean.length - 1)) ?? 0;
    return {'num': num, 'dv': dv};
  }

  Future<Map<String, String>?> _buscarPersonaPorRut(String rut) async {
    await _ensureConnection();
    final s = _splitRut(rut);
    final num = s['num'] as int;
    final dv = s['dv'] as String;
    if (num == 0 || dv.isEmpty) return null;

    final js = await _conn.getData("""
    SELECT TOP 1
      Nombres,
      ApellidoPaterno,
      ApellidoMaterno
    FROM PAPersona
WHERE RutNumero = $num
  AND RutDigito COLLATE SQL_Latin1_General_CP1_CI_AI = '$dv';

  """);

    final rows = List<Map<String, dynamic>>.from(jsonDecode(js));
    if (rows.isEmpty) return null;

    final r = rows.first;
    final nom = (r['Nombres'] ?? '').toString().trim();
    final ap = (r['ApellidoPaterno'] ?? '').toString().trim();
    final am = (r['ApellidoMaterno'] ?? '').toString().trim();
    final ape = [ap, am].where((x) => x.isNotEmpty).join(' ');
    return {'nombres': nom, 'apellidos': ape};
  }

  Future<InsertResult> insertarManualEspontaneo({
    required String rut,
    required String tipo,
    String usuario = 'TOTEM',
    String ipLocal = '0.0.0.0',
  }) async {
    await _ensureConnection();

    final per = await _buscarPersonaPorRut(rut);
    if (per != null) {
      return insertarAtencionTipoDia(
        rut: rut,
        tipo: tipo,
        nombres: per['nombres'] ?? '',
        apellidos: per['apellidos'] ?? '',
        usuario: usuario,
        ipLocal: ipLocal,
      );
    }

    final ins = await insertarAtencionTipoDia(
      rut: rut,
      tipo: tipo,
      nombres: '',
      apellidos: '',
      usuario: usuario,
      ipLocal: ipLocal,
    );

    if (!ins.success) return ins;

    final id = (ins.extra?['id'] as num?)?.toInt() ?? 0;
    final ticket = ins.ticket ?? 0;

    if (id > 0 && ticket > 0) {
      final nombreFallback = _foldForDb("Numero $ticket");
      try {
        await _conn.writeData("""
      UPDATE ALCAtenciones
         SET L28_NOMBRES = N'$nombreFallback',
             L28_APELLIDOS = ''
       WHERE id = $id
         AND (L28_NOMBRES IS NULL OR L28_NOMBRES = '');
    """);
      } catch (_) {}
    }

    return ins;
  }

  Future<InsertResult> registrarManualSmart({
    required String rut,
    required String tipo,
    int? cupoId,
  }) async {
    await _ensureConnection();

    final existente = await _fetchAtencionALC(rut, tipo);
    if (existente != null) {
      final ok = await _touchALC(existente.id);
      final tk = _bestTicketFromAtencion(existente);
      return InsertResult(
        success: ok,
        ticket: tk,
        message:
            ok
                ? 'Atención confirmada (existente), imprimiendo'
                : 'No se pudo confirmar',
        extra: {
          'id': existente.id,
          'fecha': existente.fecha,
          'tipo': existente.tipo,
          'numRut': existente.numRut,
          'nombres': existente.nombres ?? '',
          'apellidos': existente.apellidos ?? '',
          'numSol': existente.numSol ?? '',
          'correlativo': existente.correlativo,
          'correlativo1': existente.correlativo1 ?? '',
          'consumioCupo': false,
          'cupoId': cupoId,
        },
      );
    }

    final ins = await insertarManualEspontaneo(rut: rut, tipo: tipo);
    if (!ins.success) return ins;

    bool consumido = true;
    if (cupoId != null) {
      consumido = await _consumirCupoManual(cupoId);

      if (!consumido) {
        final idAtencion = (ins.extra?['id'] as num?)?.toInt();
        if (idAtencion != null && idAtencion > 0) {
          try {
            await _conn.writeData("""
              DELETE FROM ALCAtenciones WHERE id = $idAtencion;
            """);
          } catch (_) {}
        }

        return InsertResult(
          success: false,
          ticket: 0,
          message: 'Cupos agotados. No se pudo registrar la atención.',
          extra: {'consumioCupo': false, 'cupoId': cupoId},
        );
      }
    }

    return InsertResult(
      success: ins.success,
      ticket: ins.ticket,
      message: 'Atención registrada',
      extra: {...?ins.extra, 'consumioCupo': consumido, 'cupoId': cupoId},
    );
  }

  Future<bool> _consumirCupoManual(int cupoId) async {
    await _ensureConnection();

    final sql = """
SET NOCOUNT ON;

UPDATE ALCBotonesTotem WITH (ROWLOCK, UPDLOCK)
   SET cuposUsados = ISNULL(cuposUsados, 0) + 1
 WHERE id = $cupoId
   AND ISNULL(activo,0) = 1
   AND CONVERT(time, GETDATE()) BETWEEN horaInicio AND horaTermino
   AND ISNULL(cuposUsados,0) < cantidad;

SELECT ok = CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END;
""";

    final rows = List<Map<String, dynamic>>.from(
      jsonDecode(await _conn.getData(sql)),
    );
    return rows.isNotEmpty && ((rows.first['ok'] as num?)?.toInt() == 1);
  }

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  String _fmtHms(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}'
      '${t.minute.toString().padLeft(2, '0')}'
      '${t.second.toString().padLeft(2, '0')}';

  /* ───────── Pendientes práctico + utilidades ───────── */
  Future<List<Map<String, dynamic>>> practicoPendientes({
    String? rutFilter,
    int limit = 50,
    int daysBack = 3,
    bool onlyReady = true, // ya no se usa (todo acá es ready)
  }) async {
    await _ensureConnection();

    // --- Caso 1: búsqueda por RUT → último estado >= 886, PRA no rechazado,
    //             clase tomada desde EXATEO (clp.id IS NOT NULL) y misma clase vigente/no denegada
    if (rutFilter != null && rutFilter.trim().isNotEmpty) {
      final clean =
          rutFilter.replaceAll(RegExp(r'[^0-9kK-]'), '').toUpperCase();
      final parts = clean.split('-');
      if (parts.length != 2) return <Map<String, dynamic>>[];

      final rutNum = int.tryParse(parts[0]) ?? 0;
      final dv = parts[1];
      if (rutNum <= 0 || dv.isEmpty) return <Map<String, dynamic>>[];

      final js = await _conn.getData("""
SELECT TOP 1
  pa.RutNumero,
  pa.RutDigito,
  CONCAT(pa.Nombres,' ',pa.ApellidoPaterno,' ',pa.ApellidoMaterno) AS Nombre,
  af.FechaResultado
FROM PAPersona pa
JOIN ALCMaestro            am  ON pa.PAPersonaId = am.PAPersonaId
JOIN ALCEstados            ae  ON am.id          = ae.ALCMaestro_id
JOIN ALCEstados_Flujos     af  ON ae.id          = af.ALCEstado_id

-- PRA último (opcional)
OUTER APPLY (
  SELECT TOP 1 p.*
  FROM ALCExapra p
  WHERE p.ALCMaestro_id = am.id
  ORDER BY p.id DESC
) pra_last

-- Clase desde EXATEO (último registro)
OUTER APPLY (
  SELECT TOP 1 e.*
  FROM ALCExateo e
  WHERE e.ALCMaestro_id = am.id
  ORDER BY e.id DESC
) exa_last

-- Catálogo de clases según EXATEO
LEFT JOIN ALCParametros_Clases clp
       ON clp.id = exa_last.ALCParametros_Clases_id

-- Estado de esa misma clase en maestro
LEFT JOIN ALCClases cla
       ON cla.ALCMaestro_id = am.id
      AND cla.ALCParametros_Clase_id = clp.id

WHERE pa.RutNumero = $rutNum
  AND pa.RutDigito COLLATE SQL_Latin1_General_CP1_CI_AI = '$dv'
  AND am.L01_ESTADO LIKE '%SOL%'
  AND ae.ALCParametro_General_Etapa_id >= 886
  AND (pra_last.ALCMaestro_id IS NULL OR pra_last.L09_RESULT <> 'R')
  AND clp.id IS NOT NULL
  AND (cla.claseDenegada = 0 OR cla.Vigente = 1)
ORDER BY am.ID DESC, af.FechaResultado DESC, COALESCE(exa_last.id, 0) DESC;
""");

      final rows = List<Map<String, dynamic>>.from(jsonDecode(js));
      if (rows.isEmpty) return <Map<String, dynamic>>[];

      final r = rows.first;
      final ultimoMov =
          (r['FechaResultado'] ?? DateTime.now().toString()).toString();

      return [
        {
          'rut':
              '${(r['RutNumero'] as num?)?.toInt() ?? 0}-${(r['RutDigito'] ?? '').toString()}',
          'nombre': (r['Nombre'] ?? '').toString().trim(),
          'pendCount': 0,
          'menorEtapaPendiente': 0,
          'ultimoMovimiento':
              ultimoMov.length >= 19 ? ultimoMov.substring(0, 19) : ultimoMov,
        },
      ];
    }

    // --- Caso 2: sin RUT → listado “aptos” recientes con los mismos filtros
    final js2 = await _conn.getData("""
;WITH ult AS (
  SELECT
    pa.RutNumero,
    pa.RutDigito,
    CONCAT(pa.Nombres,' ',pa.ApellidoPaterno,' ',pa.ApellidoMaterno) AS Nombre,
    af.FechaResultado,
    ROW_NUMBER() OVER (PARTITION BY pa.PAPersonaId ORDER BY am.ID DESC, af.FechaResultado DESC) AS rn
  FROM PAPersona pa
  JOIN ALCMaestro        am ON pa.PAPersonaId = am.PAPersonaId
  JOIN ALCEstados        ae ON am.id          = ae.ALCMaestro_id
  JOIN ALCEstados_Flujos af ON ae.id          = af.ALCEstado_id

  OUTER APPLY (
    SELECT TOP 1 p.* FROM ALCExapra p
    WHERE p.ALCMaestro_id = am.id
    ORDER BY p.id DESC
  ) pra_last

  OUTER APPLY (
    SELECT TOP 1 e.*
    FROM ALCExateo e
    WHERE e.ALCMaestro_id = am.id
    ORDER BY e.id DESC
  ) exa_last

  LEFT JOIN ALCParametros_Clases clp
         ON clp.id = exa_last.ALCParametros_Clases_id

  LEFT JOIN ALCClases cla
         ON cla.ALCMaestro_id = am.id
        AND cla.ALCParametros_Clase_id = clp.id

  WHERE am.L01_ESTADO LIKE '%SOL%'
    AND ae.ALCParametro_General_Etapa_id >= 886
    AND (pra_last.ALCMaestro_id IS NULL OR pra_last.L09_RESULT <> 'R')
    AND clp.id IS NOT NULL
    AND (cla.claseDenegada = 0 OR cla.Vigente = 1)
    AND af.FechaResultado >= DATEADD(DAY, -$daysBack, CONVERT(date, GETDATE()))
)
SELECT TOP ($limit)
  RutNumero,
  RutDigito,
  Nombre,
  CONVERT(varchar(19), FechaResultado, 120) AS UltimoMovimiento
FROM ult
WHERE rn = 1
ORDER BY FechaResultado DESC, Nombre ASC;
""");

    final rows2 = List<Map<String, dynamic>>.from(jsonDecode(js2));
    return rows2.map((r) {
      final rutNumero = (r['RutNumero'] as num?)?.toInt() ?? 0;
      final dv = (r['RutDigito'] ?? '').toString();
      return {
        'rut': '$rutNumero-$dv',
        'nombre': (r['Nombre'] ?? '').toString().trim(),
        'pendCount': 0,
        'menorEtapaPendiente': 0,
        'ultimoMovimiento': (r['UltimoMovimiento'] ?? '').toString(),
      };
    }).toList();
  }

  Future<String?> nombreCompletoPorRut(String rut) async {
    final per = await _buscarPersonaPorRut(rut);
    if (per == null) return null;
    final nom = (per['nombres'] ?? '').toString().trim();
    final ape = (per['apellidos'] ?? '').toString().trim();
    final full = [nom, ape].where((s) => s.isNotEmpty).join(' ');
    return full.isEmpty ? null : full;
  }

  Future<CupoCheck> _checkCupoUnionPorLabels({
    required List<String> labels,
    bool requiereApertura = true,
  }) async {
    await _ensureConnection();

    final allAliases = <String>{};
    for (final lab in labels) {
      for (final a in DatabaseConfig.tramitesByLabel(lab)) {
        allAliases.add(_toAnsi(a).replaceAll("'", "''"));
      }
    }
    if (allAliases.isEmpty) {
      return const CupoCheck(
        ok: false,
        cupoId: null,
        disponibles: 0,
        motivo: 'No se han habilitado cupos para este trámite',
        horaInicio: '00:00:00',
        horaTermino: '00:00:00',
        dentroHorario: false,
      );
    }
    final inList = allAliases.map((a) => "N'$a'").join(',');

    final sql = """
SELECT
  id,
  tramite,
  CONVERT(varchar(8), horaInicio, 108)  AS horaInicio,
  CONVERT(varchar(8), horaTermino, 108) AS horaTermino,
  cantidad,
  ISNULL(cuposUsados,0) AS cuposUsados,
  CASE WHEN CONVERT(time, GETDATE()) BETWEEN horaInicio AND horaTermino THEN 1 ELSE 0 END AS dentro
FROM ALCBotonesTotem WITH (READPAST)
WHERE ISNULL(activo,0)=1
  AND tramite COLLATE SQL_Latin1_General_CP1_CI_AI IN ($inList);
""";

    final rows = List<Map<String, dynamic>>.from(
      jsonDecode(await _conn.getData(sql)),
    );
    if (rows.isEmpty) {
      return const CupoCheck(
        ok: false,
        cupoId: null,
        disponibles: 0,
        motivo: 'No se han habilitado cupos para este trámite',
        horaInicio: '00:00:00',
        horaTermino: '00:00:00',
        dentroHorario: false,
      );
    }

    final abiertos =
        !requiereApertura ||
        rows.any((r) => (r['cuposUsados'] as num?).asInt >= 1);

    var anyActivo = false, sumActivo = 0, sumTotal = 0;
    int? pickId;
    var bestStock = -1;
    String pickIni = '00:00:00', pickFin = '00:00:00';

    for (final r in rows) {
      final cant = (r['cantidad'] as num?).asInt;
      final usados = (r['cuposUsados'] as num?).asInt;
      final stock = cant - usados;
      sumTotal += stock;

      final dentro = (r['dentro'] as num?).asInt == 1;
      if (dentro) {
        anyActivo = true;
        sumActivo += stock;
        if (stock > 0 && stock > bestStock) {
          bestStock = stock;
          pickId = (r['id'] as num?).asInt;
          pickIni = (r['horaInicio'] as Object?).asStr;
          pickFin = (r['horaTermino'] as Object?).asStr;
        }
      }
    }

    if (!abiertos) {
      final rang = rows.first;
      return CupoCheck(
        ok: false,
        cupoId: (rang['id'] as num?)?.asInt,
        disponibles: anyActivo ? sumActivo : sumTotal,
        motivo: 'No se han habilitado cupos para este trámite',
        horaInicio: (rang['horaInicio'] as Object?).asStr,
        horaTermino: (rang['horaTermino'] as Object?).asStr,
        dentroHorario: anyActivo,
      );
    }

    if (!anyActivo) {
      rows.sort(
        (a, b) => ((a['horaInicio'] as Object?).asStr).compareTo(
          (b['horaInicio'] as Object?).asStr,
        ),
      );

      final next = rows.first;
      return CupoCheck(
        ok: false,
        cupoId: (next['id'] as num?)?.asInt,
        disponibles: 0,
        motivo: 'Fuera de horario',
        horaInicio: (next['horaInicio'] as Object?).asStr,
        horaTermino: (next['horaTermino'] as Object?).asStr,
        dentroHorario: false,
      );
    }

    if (sumActivo <= 0) {
      return CupoCheck(
        ok: false,
        cupoId: pickId,
        disponibles: 0,
        motivo: 'Cupos agotados por hoy',
        horaInicio: pickIni,
        horaTermino: pickFin,
        dentroHorario: true,
      );
    }

    return CupoCheck(
      ok: true,
      cupoId: pickId,
      disponibles: sumActivo,
      motivo: 'OK',
      horaInicio: pickIni,
      horaTermino: pickFin,
      dentroHorario: true,
    );
  }

  /// Toca un botón del tótem (por label) y consume su cupo.
  /// - Usa el label exacto del botón (como está en ALCBotonesTotem.tramite)
  Future<InsertResult> emitirPorBoton({
    required String rut,
    required String label,
    bool requiereApertura = true,
  }) async {
    await _ensureConnection();

    final cupo = await checkCupoManualPorLabel(
      labelTramite: label,
      requiereApertura: requiereApertura,
    );

    if (!cupo.ok || cupo.cupoId == null) {
      return InsertResult(success: false, message: cupo.motivo);
    }

    // Mapea el label a tipo (p.ej. 'P','R','D','E','C','Z'...)
    final tipo = DatabaseConfig.tipoByLabel(label);

    // Inserta (o reimprime si ya existe) y, si corresponde, consume 1 cupo
    return registrarManualSmart(rut: rut, tipo: tipo, cupoId: cupo.cupoId);
  }

  /// Pliega texto a ASCII “seguro” para VARCHAR legacy (ñ→n, tildes fuera, etc.)
  /// y escapa comillas simples para SQL. Sin dependencias externas.
  String _foldForDb(String s) {
    if (s.isEmpty) return s;

    const map = {
      // A
      'Á': 'A',
      'À': 'A',
      'Â': 'A',
      'Ä': 'A',
      'Ã': 'A',
      'Å': 'A',
      'Ā': 'A',
      'Ă': 'A',
      'Ą': 'A',
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'ā': 'a',
      'ă': 'a',
      'ą': 'a',
      // E
      'É': 'E',
      'È': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'Ē': 'E',
      'Ĕ': 'E',
      'Ė': 'E',
      'Ę': 'E',
      'Ě': 'E',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'ē': 'e',
      'ĕ': 'e',
      'ė': 'e',
      'ę': 'e',
      'ě': 'e',
      // I
      'Í': 'I',
      'Ì': 'I',
      'Î': 'I',
      'Ï': 'I',
      'Ī': 'I',
      'Ĭ': 'I',
      'Į': 'I',
      'İ': 'I',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ī': 'i',
      'ĭ': 'i',
      'į': 'i',
      'ı': 'i',
      // O
      'Ó': 'O',
      'Ò': 'O',
      'Ô': 'O',
      'Ö': 'O',
      'Õ': 'O',
      'Ō': 'O',
      'Ŏ': 'O',
      'Ő': 'O',
      'Ø': 'O',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ō': 'o',
      'ŏ': 'o',
      'ő': 'o',
      'ø': 'o',
      // U
      'Ú': 'U',
      'Ù': 'U',
      'Û': 'U',
      'Ü': 'U',
      'Ū': 'U',
      'Ŭ': 'U',
      'Ů': 'U',
      'Ű': 'U',
      'Ų': 'U',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ū': 'u',
      'ŭ': 'u',
      'ů': 'u',
      'ű': 'u',
      'ų': 'u',
      // Y
      'Ý': 'Y', 'Ÿ': 'Y', 'ý': 'y', 'ÿ': 'y',
      // C / N / S / Z / AE / SS, etc.
      'Ç': 'C', 'ç': 'c',
      'Ñ': 'N', 'ñ': 'n',
      'Š': 'S', 'š': 's',
      'Ž': 'Z', 'ž': 'z',
      'Æ': 'AE', 'æ': 'ae',
      'ß': 'ss',
      // comillas/guiones “smart” y varios
      '“': '"',
      '”': '"',
      '‘': "'",
      '’': "'",
      '´': "'",
      '`': "'",
      '‹': "'",
      '›': "'",
      '«': '"',
      '»': '"',
      '–': '-', '—': '-', '•': '-', '·': '.', 'º': 'o', '°': 'o', 'ª': 'a',
    };

    final sb = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      sb.write(map[ch] ?? ch);
    }

    // Si vinieran ya en forma combinante, borra marcas U+0300..U+036F
    final noCombining = sb.toString().replaceAll(
      RegExp(r'[\u0300-\u036f]'),
      '',
    );

    // Escapa comillas simples para SQL
    return noCombining.replaceAll("'", "''");
  }

  // ====== PEGAR DENTRO DE LA CLASE DatabaseService (sin tocar nada más) ======

  // Versión detallada (devuelve motivo del error/éxito)
  Future<EndpointResult> enviarPracticoTabletCrearWithReason({
    required String rut,
    required String label,
    required DateTime fechaExamen,
  }) async {
    await _ensureConnection();

    // 1) Map label -> "B" | "C"
    final l = label.toLowerCase();
    final tramite =
        (l.contains('c y cr') || l.contains(' práctico c') || l.endsWith(' c'))
            ? 'C'
            : 'B';

    // 2) RUT
    final s = _splitRut(rut);
    final numero = s['num'] as int;
    final digito = (s['dv'] as String);
    if (numero <= 0 || digito.isEmpty) {
      debugPrint('[PRACTICO] RUT inválido: "$rut"');
      return const EndpointResult(
        ok: false,
        status: -2,
        message: 'RUT inválido (falta DV o formato)',
        body: null,
      );
    }

    // 3) Consulta: clase desde ALCExateo; PRA opcional; etapa >= 886.
    final js = await _conn.getData("""
SELECT TOP 1
  pa.PAPersonaId,
  pa.RutNumero,
  pa.RutDigito,
  pa.Nombres,
  pa.ApellidoPaterno,
  pa.ApellidoMaterno,
  am.id AS AM_ID,
  am.FechaSolicitud,
  -- Oportunidad calculada:
  CASE 
    WHEN pra_first.L09_RESULT = 'P' THEN 2                  -- primera oportunidad == 'P' => 2
    WHEN pra_last.L09_OPORTU IS NULL THEN 1                 -- sin PRA aún
    ELSE pra_last.L09_OPORTU                                -- caso normal: última oportunidad registrada
  END AS L09_OPORTU,
  clp.Nombre AS clase,
  clp.id
FROM PAPersona pa
JOIN ALCMaestro            am  ON pa.PAPersonaId = am.PAPersonaId
JOIN ALCEstados            ae  ON am.id          = ae.ALCMaestro_id
JOIN ALCEstados_Flujos     af  ON ae.id          = af.ALCEstado_id

-- PRA opcional (si hay, usamos L09_OPORTU)
OUTER APPLY (
  SELECT TOP 1 p.*
  FROM ALCExapra p
  WHERE p.ALCMaestro_id = am.id
  ORDER BY p.id DESC
) pra_last

-- **Primer PRA** (para saber si la primera oportunidad fue 'P')
OUTER APPLY (
  SELECT TOP 1 p.L09_RESULT
  FROM ALCExapra p
  WHERE p.ALCMaestro_id = am.id
  ORDER BY p.id ASC
) pra_first

-- Clase desde EXATEO (último registro)
OUTER APPLY (
  SELECT TOP 1 e.*
  FROM ALCExateo e
  WHERE e.ALCMaestro_id = am.id
  ORDER BY e.id DESC
) exa_last

-- Catálogo de clases según EXATEO
LEFT JOIN ALCParametros_Clases clp
       ON clp.id = exa_last.ALCParametros_Clases_id

-- Estado de la clase en maestro (para filtrar vigente/denegada)
LEFT JOIN ALCClases cla
       ON cla.ALCMaestro_id = am.id
      AND cla.ALCParametros_Clase_id = clp.id

WHERE 
  pa.RutNumero = $numero
  AND pa.RutDigito COLLATE SQL_Latin1_General_CP1_CI_AI = '$digito'
  AND am.L01_ESTADO LIKE '%SOL%'
  AND ae.ALCParametro_General_Etapa_id >= 886          -- práctico
  AND clp.id IS NOT NULL                               -- debe existir clase tomada desde EXATEO
  AND (cla.claseDenegada = 0 OR cla.Vigente = 1)       -- misma clase, vigente/no denegada
ORDER BY 
  COALESCE(pra_last.id, 0) DESC,      -- primero por id del práctico
  am.ID DESC, 
  af.FechaResultado DESC, 
  COALESCE(exa_last.id, 0) DESC;
""");

    final rows = List<Map<String, dynamic>>.from(jsonDecode(js));
    if (rows.isEmpty) {
      debugPrint(
        '[PRACTICO] Sin fila (teórico/clase/etapa) para construir payload.',
      );
      return const EndpointResult(
        ok: false,
        status: -2,
        message:
            'No se encontraron datos válidos (clase teórica o etapa práctica no cumplen).',
        body: null,
      );
    }

    // 4) Payload
    String only(Object? v) => (v ?? '').toString().trim();
    final x = rows.first;
    final nombres = only(x['Nombres']);
    final apePat = only(x['ApellidoPaterno']);
    final apeMat = only(x['ApellidoMaterno']);
    final repite = int.tryParse(only(x['L09_OPORTU'])) ?? 0;
    final amId = int.tryParse(only(x['AM_ID'])) ?? 0;
    final fechaSol =
        DateTime.tryParse(only(x['FechaSolicitud'])) ?? DateTime.now();

    final payload = {
      "L82_NUMRUT":
          '$numero$digito', // si tu API requiere con DV: "$numero-$digito"
      "L82_NUMSOL":
          amId.toString(), // referencia interna (AM_ID) como numsol “local”
      "L82_NOMBRES": nombres,
      "L82_APELLIDO_PAT": apePat,
      "L82_APELLIDO_MAT": apeMat,
      "L82_TRAMITE": tramite, // "B" | "C"
      "L82_REPITE_EXAMEN": repite,
      "L82_FECHA_SOL": _fmtDate(fechaSol), // "YYYY-MM-DD HH:mm:ss"
      "L82_FECHA_EXA": _fmtDate(
        fechaExamen,
      ), // "YYYY-MM-DD HH:mm:ss" (momento de ticket)
      "L82_ESTADOSOL": "P",
      "COMUNA": "PUENTE ALTO",
    };

    // 5) POST
    final url =
        (DatabaseConfig.practicoCrearUrl.isNotEmpty)
            ? DatabaseConfig.practicoCrearUrl
            : "https://apipuente.reservandotuhora.cl/apipractico/practico-tablet/crear";

    debugPrint('[PRACTICO] POST $url');
    debugPrint('[PRACTICO] Payload => ${jsonEncode(payload)}');

    http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse(url),
            headers: {
              "Content-Type": "application/json; charset=utf-8",
              "Accept": "application/json",
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[PRACTICO] Error HTTP/timeout: $e');
      return EndpointResult(
        ok: false,
        status: -1,
        message: 'Error de red/timeout: $e',
        body: null,
      );
    }

    debugPrint('[PRACTICO] HTTP ${resp.statusCode}');
    debugPrint('[PRACTICO] Body: ${resp.body}');

    // 6) Parsear mensaje legible
    String? nice;
    bool? successFlag;
    try {
      final b = jsonDecode(resp.body);
      if (b is Map) {
        if (b['success'] is bool) successFlag = b['success'] as bool;
        if (b['message'] is String)
          nice =
              (nice == null)
                  ? b['message'] as String
                  : '$nice | ${b['message']}';
        if (b['error'] is String)
          nice =
              (nice == null) ? b['error'] as String : '$nice | ${b['error']}';

        if (b['resultados'] is List && (b['resultados'] as List).isNotEmpty) {
          final r0 = (b['resultados'] as List).first;
          if (r0 is Map && r0['message'] is String) {
            final msg = r0['message'] as String;
            nice = (nice == null) ? msg : '$nice | $msg';
          }
        }
      }
    } catch (_) {
      // si no es JSON, dejamos nice como esté y devolvemos body crudo
    }

    final in2xx = resp.statusCode >= 200 && resp.statusCode < 300;
    final ok = in2xx && (successFlag == null ? true : successFlag == true);

    // Si vino un mensaje que contiene “error”, márcalo como fail aunque sea 2xx
    final lowered = (nice ?? '').toLowerCase();
    final looksError =
        lowered.contains('error') ||
        lowered.contains('fall') ||
        lowered.contains('deneg') ||
        lowered.contains('inválid') ||
        lowered.contains('invalid');

    return EndpointResult(
      ok: ok && !looksError,
      status: resp.statusCode,
      message: nice,
      body: resp.body,
    );
  }

  // Wrapper boolean (para compatibilidad con código existente)
  Future<bool> enviarPracticoTabletCrear({
    required String rut,
    required String label,
    required DateTime fechaExamen,
  }) async {
    final r = await enviarPracticoTabletCrearWithReason(
      rut: rut,
      label: label,
      fechaExamen: fechaExamen,
    );
    return r.ok;
  }

  // Wrapper público “tablet/crear” (detalle para la UI)
  Future<EndpointResult> crearPracticoTabletWithReason({
    required String rutFormateado,
    required String labelTramite,
    required DateTime fechaExamen,
  }) {
    return enviarPracticoTabletCrearWithReason(
      rut: rutFormateado,
      label: labelTramite,
      fechaExamen: fechaExamen,
    );
  }

  // Mantén el que ya usas si no quieres tocar más sitios
  Future<bool> crearPracticoTablet({
    required String rutFormateado,
    required String labelTramite,
    required DateTime fechaExamen,
  }) {
    return enviarPracticoTabletCrear(
      rut: rutFormateado,
      label: labelTramite,
      fechaExamen: fechaExamen,
    );
  }
}
