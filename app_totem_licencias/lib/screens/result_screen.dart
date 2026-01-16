// lib/screens/result_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/database_config.dart';

import '../models/reserva.dart';
import '../models/practico_result.dart';
import '../models/insert_result.dart';
import '../models/etapa.dart';
import '../models/atencion.dart';

import '../providers/reserva_providers.dart';
import '../services/database_service.dart';
import 'app_header.dart';

// Impresión RAW ESC/POS
import '../printing/raw_escpos.dart';
import '../printing/print_config.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  static const int _initialSeconds = 8;
  late int _secondsRemaining;
  Timer? _timer;
  bool _timerStarted = false;
  bool _printed = false;

  bool _insertStarted = false;
  InsertResult? _insertResult;
  dynamic _originalData;

  bool _ticketFetchStarted = false;
  int? _ticketOverride;

  double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /*──────────────── helpers UI ───────────────*/
  Widget _infoRow(String label, String value, double scale, {Color? color}) =>
      Padding(
        padding: EdgeInsets.symmetric(vertical: 4 * scale),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140 * scale,
              child: Text(
                label,
                style: TextStyle(fontSize: 20 * scale, color: Colors.black87),
              ),
            ),
            SizedBox(width: 10 * scale),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 20 * scale,
                  fontWeight: FontWeight.w700,
                  color: color ?? Colors.black,
                ),
                textAlign: TextAlign.left,
                softWrap: true,
              ),
            ),
          ],
        ),
      );

  void _startTimer({int? seconds}) {
    if (_timerStarted) return;
    _timerStarted = true;
    _secondsRemaining = seconds ?? _initialSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsRemaining == 0) {
        t.cancel();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        }
      } else {
        if (mounted) setState(() => _secondsRemaining--);
      }
    });
  }

  Future<String> _pickLicPrinter() async {
  final installed = EscPosRawPrinter.listInstalledPrinters();
  final pref = PrintConfig.printerNameLicencias;
  if (installed.contains(pref)) return pref;

  // usa la misma que sí probaste (práctico)
  final fallback = PrintConfig.printerNamePractico;
  if (installed.contains(fallback)) return fallback;

  // último recurso
  return installed.isNotEmpty ? installed.first : pref;
}


  String formatearFecha(String f) {
    final dia = f.substring(6, 8);
    final mes = f.substring(4, 6);
    final anio = f.substring(0, 4);
    const meses = {
      '01': 'Enero',
      '02': 'Febrero',
      '03': 'Marzo',
      '04': 'Abril',
      '05': 'Mayo',
      '06': 'Junio',
      '07': 'Julio',
      '08': 'Agosto',
      '09': 'Septiembre',
      '10': 'Octubre',
      '11': 'Noviembre',
      '12': 'Diciembre',
    };
    return '$dia de ${meses[mes]} de $anio';
  }

  /*────────── INSERT + IMPRESIÓN ESC/POS RAW ─────────*/
void _insertIfNeeded({required String rut, required dynamic obj}) {
  if (_insertStarted) return;
  _insertStarted = true;
  _originalData = obj;

  // ───────── RESERVA (ONLINE / LICENCIAS) ─────────
if (obj is Reserva) {
  DatabaseService.instance.fetchAndInsert(rut, 'ON').then((res) async {
    if (!mounted) return;
    setState(() => _insertResult = res);
    _startTimer();

    if (res.success && !_printed) {
      _printed = true;
      try {
        final cola = await _pickLicPrinter();
        final escpos = EscPosRawPrinter(
          printerName: cola,
          codepage: PrintConfig.codepage,
        );
        await escpos.printReserva(
          obj,
          fechaFormateada: formatearFecha(obj.fechaCitacion),
          correlativoDia: res.ticket, // 👈 pasa el 1..N del día a la impresión
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al imprimir: $e')),
        );
      }
    }
  });
  return;
}

  // ───────── EXAMEN PRÁCTICO ─────────
  if (obj is PracticoResult) {
    DatabaseService.instance.fetchAndInsert(rut, 'PR').then((res) async {
      if (!mounted) return;
      setState(() => _insertResult = res);
      _startTimer();

      // Si tiene etapas pendientes, no imprime
      if (!res.success) return;

      if (!_printed) {
        _printed = true;
        try {
          final escpos = EscPosRawPrinter(
            printerName: PrintConfig.printerNamePractico,
            codepage: PrintConfig.codepage,
          );
          final tk = res.ticket ?? 0;
          if (tk > 0) {
            await escpos.printPracticoTicket(nombre: obj.nombre, ticket: tk);
          } else {
            await escpos.printPractico(obj);
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al imprimir: $e')),
          );
        }
      }
    });
    return;
  }
}

  /*──────────────── UI builders centrados ───────────────*/
  Widget _centeredCard(Widget child, double maxWidth) {
    return Expanded(
      child: LayoutBuilder(
        builder:
            (context, c) => SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }

  Widget _resultCard({
    required IconData icon,
    required Color tone,
    required String title,
    required String subtitle,
    int? ticket,
    required List<Widget> body,
    required double scale,
  }) {
    final toneBg = tone.withOpacity(0.08);
    final chipBg = tone.withOpacity(0.18);
    return Card(
      color: toneBg,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          28 * scale,
          28 * scale,
          28 * scale,
          32 * scale,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40 * scale,
              backgroundColor: tone.withOpacity(0.12),
              child: Icon(icon, size: 48 * scale, color: tone),
            ),
            SizedBox(height: 16 * scale),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 40 * scale,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 8 * scale),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20 * scale,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (ticket != null && ticket > 0) ...[
              SizedBox(height: 20 * scale),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 16 * scale,
                  vertical: 10 * scale,
                ),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(12 * scale),
                ),
                child: Text(
                  'TICKET #$ticket',
                  style: TextStyle(
                    color: tone.darken(),
                    fontWeight: FontWeight.w900,
                    fontSize: 22 * scale,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
            SizedBox(height: 24 * scale),
            const Divider(height: 1),
            SizedBox(height: 16 * scale),
            ...body,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final scale = _clamp(w / 1080, 1.0, 1.35);
    final maxCardWidth = _clamp(w * 0.92, 900, 1200);

    // ====== ARGUMENTOS MODO PRÁCTICO ======
    final Map<String, dynamic> rawArgs =
        ModalRoute.of(context)?.settings.arguments is Map
            ? Map<String, dynamic>.from(
              ModalRoute.of(context)!.settings.arguments as Map,
            )
            : {};

    final String? modeArg = rawArgs['mode'] as String?;
    final String nombreArg = (rawArgs['nombre'] ?? '') as String;
    final List etapasRaw = (rawArgs['etapas'] as List?) ?? const [];
    final int? ticketArg = rawArgs['ticket'] as int?;
    final String rutArg = (rawArgs['rut'] ?? '') as String;

    // Nombres de etapas
    const stepNames = {
      880: 'CAJA',
      881: 'FOTOGRAFÍA',
      882: 'EXAMEN PSICOMÉTRICO',
      883: 'EXAMEN SENSOMÉTRICO',
      884: 'ENTREVISTA MÉDICA',
      885: 'EXAMEN TEÓRICO',
    };

    bool _etapaPend(Map e) {
      final id = (e['EtapaId'] as num?)?.toInt() ?? 0;
      final r = (e['Resultado'] ?? '').toString();
      return id <= 885 && (r == 'E' || r == 'S');
    }

    // ── Mostrar “pendientes” (sin número) ─────────────────────────
    if (modeArg == 'practico_estado') {
      _startTimer();
      final faltantes =
          etapasRaw.where((e) => _etapaPend(e as Map)).cast<Map>().toList();

      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const AppHeader(),
              _centeredCard(
                _resultCard(
                  icon: Icons.error_outline,
                  tone: Colors.red.shade700,
                  title: 'No puede continuar',
                  subtitle: 'Tiene etapas pendientes',
                  ticket: null,
                  scale: scale,
                  body: [
                    if (nombreArg.isNotEmpty)
                      _infoRow('Nombre:', nombreArg, scale),
                    const SizedBox(height: 8),
                    ...faltantes.map((e) {
                      final id = (e['EtapaId'] as num).toInt();
                      return _infoRow(
                        '$id  ${stepNames[id] ?? ''}',
                        '❌ Pendiente',
                        scale,
                        color: Colors.red,
                      );
                    }),
                  ],
                ),
                maxCardWidth,
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 20 * scale),
                child: Text(
                  'Volviendo en $_secondsRemaining s',
                  style: TextStyle(
                    fontSize: 18 * scale,
                    fontStyle: FontStyle.italic,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (modeArg == 'practico_ticket') {
      // pedir número por SP una sola vez
      if (!_ticketFetchStarted) {
        _ticketFetchStarted = true;
        Future.microtask(() async {
          try {
            final t = await DatabaseService.instance.ensurePracticoTicket(
              rut: rutArg,
              nombres: nombreArg,
            );
            if (!mounted) return;
            setState(() => _ticketOverride = t);

            if (!_printed && t > 0) {
              _printed = true;
              final escpos = EscPosRawPrinter(
                printerName: PrintConfig.printerNamePractico,
                codepage: PrintConfig.codepage,
              );
              await escpos.printPracticoTicket(nombre: nombreArg, ticket: t);
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al generar número: $e')),
            );
          }
        });
      }
      // 3) ahora recién arrancamos el timer (más largo para dar tiempo)
      if (!_timerStarted) {
        _startTimer(seconds: 8);
      }

      final tk = _ticketOverride ?? ticketArg ?? 0;

      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const AppHeader(),
              _centeredCard(
                _resultCard(
                  icon: Icons.confirmation_number_outlined,
                  tone: Colors.teal.shade700,
                  title: 'Examen práctico',
                  subtitle: 'Preséntese con este número',
                  ticket: tk > 0 ? tk : null,
                  scale: scale,
                  body: [
                    if (nombreArg.isNotEmpty)
                      _infoRow('Nombre:', nombreArg, scale),
                    if (rutArg.isNotEmpty) _infoRow('RUT:', rutArg, scale),
                    if (tk == 0)
                      Padding(
                        padding: EdgeInsets.only(top: 8 * scale),
                        child: Text(
                          'Generando número...',
                          style: TextStyle(
                            fontSize: 18 * scale,
                            fontStyle: FontStyle.italic,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                  ],
                ),
                maxCardWidth,
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 20 * scale),
                child: Text(
                  'Volviendo en $_secondsRemaining s',
                  style: TextStyle(
                    fontSize: 18 * scale,
                    fontStyle: FontStyle.italic,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // === Arguments (UNA sola vez) ===
    final args = ModalRoute.of(context)!.settings.arguments;

    InsertResult? alcaRes;
    String? alcaLabel;

    String rut = '';
    List<Etapa> etapasArg = [];

    String? flowArg;
    String? codeArg;
    String? labelArg;

    if (args is String) {
      rut = args;
    } else if (args is Map) {
      rut = args['rut'] as String? ?? '';
      etapasArg = (args['etapas'] as List<Etapa>?) ?? [];
      alcaRes = args['alcaResult'] as InsertResult?;
      alcaLabel = args['alcaLabel'] as String?;
      flowArg = args['flow'] as String?;
      codeArg = args['code'] as String?;
      labelArg = args['label'] as String?;
    }

    // 🛡️ BLINDAJE ALC (manual/espontáneo: confirma si existe, o CREA si no)
    int? cupoIdArg;
    if (args is Map) {
      cupoIdArg = args['cupoId'] as int?;
    }

if (flowArg == 'alca' && alcaRes == null && !_insertStarted) {
  _insertStarted = true;
  Future.microtask(() async {
    try {
      // si viene label úsalo; si no, deriva desde el code
      final String? label =
          labelArg ?? DatabaseConfig.labelByTipo(codeArg ?? DatabaseConfig.defaultTipo);

      final InsertResult res = (label != null)
          ? await DatabaseService.instance.emitirPorBoton(
              rut: rut,
              label: label,
              requiereApertura: false, // o true si quieres respetar la apertura
            )
          : await DatabaseService.instance.registrarManualSmart(
              rut: rut,
              tipo: codeArg ?? DatabaseConfig.defaultTipo,
              cupoId: cupoIdArg,
            );

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/result',
        arguments: {
          'alcaResult': res,
          'alcaLabel': label ?? labelArg ?? codeArg ?? 'P',
          'rut': rut,
          'flow': 'alca',
          'code': codeArg ?? 'P',
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/error', arguments: e.toString());
    }
  });
  return const Scaffold(body: Center(child: CircularProgressIndicator()));
}
    // === ALC (manual nuevo)
// === ALC (manual nuevo)
if (alcaRes != null) {
  _startTimer();

  final Map<String, dynamic> data =
      (alcaRes!.extra is Map)
          ? Map<String, dynamic>.from(alcaRes!.extra as Map)
          : <String, dynamic>{};

  Atencion? atencion;
  if (alcaRes!.success) {
    int safeId = 0;

    final dynamic rawId = data['id'];
    if (rawId is int) {
      safeId = rawId;
    } else if (rawId is String) {
      safeId = int.tryParse(rawId) ?? 0;
    }
    if (safeId == 0) safeId = alcaRes!.ticket ?? 0;

    if (safeId > 0) {
      atencion = Atencion(
        id: safeId,
        fecha: (data['fecha'] ?? '').toString(),
        tipo: (data['tipo'] ?? '').toString(),
        correlativo: (data['correlativo'] ?? '').toString(),
        numRut: (data['numRut'] ?? '').toString(),
        nombres:
            (data['nombres']?.toString().isEmpty ?? true)
                ? null
                : data['nombres'].toString(),
        apellidos:
            (data['apellidos']?.toString().isEmpty ?? true)
                ? null
                : data['apellidos'].toString(),
        numSol:
            (data['numSol']?.toString().isEmpty ?? true)
                ? null
                : data['numSol'].toString(),
        correlativo1:
            (data['correlativo1']?.toString().isEmpty ?? true)
                ? null
                : data['correlativo1'].toString(),
        hora: null,
        asignado: null,
        atendido: null,
      );
    }
  }

  if (!_printed && alcaRes!.success && atencion != null) {
    _printed = true;
    Future.microtask(() async {
      try {
        final cola = await _pickLicPrinter();
        final escpos = EscPosRawPrinter(
          printerName: cola,
          codepage: PrintConfig.codepage,
        );
        await escpos.printAlcAtencion(
          atencion!,
          ticket: alcaRes!.ticket ?? atencion!.id,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al imprimir: $e')),
        );
      }
    });
  }

  final ok = alcaRes!.success && atencion != null;
  return Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const AppHeader(),
          _centeredCard(
            _resultCard(
              icon: ok ? Icons.receipt_long_rounded : Icons.error_outline,
              tone: ok ? Colors.teal.shade700 : Colors.red.shade700,
              title: ok ? 'Voucher generado' : 'No se encontró atención',
              subtitle:
                  alcaRes!.message ??
                  (ok ? 'Espere su llamado' : 'Sin registro para hoy'),
              ticket: ok ? (alcaRes!.ticket ?? atencion!.id) : null,
              scale: scale,
              body: [
                if (alcaLabel != null) _infoRow('Trámite:', alcaLabel!, scale),
                if (ok &&
                    ((atencion!.nombres ?? '').isNotEmpty ||
                        (atencion!.apellidos ?? '').isNotEmpty))
                  _infoRow(
                    'Nombre:',
                    '${atencion!.nombres ?? ''} ${atencion!.apellidos ?? ''}'
                        .trim(),
                    scale,
                  ),
                if (ok) _infoRow('RUT:', atencion!.numRut, scale),
                if (ok && (atencion!.numSol?.isNotEmpty ?? false))
                  _infoRow('N° Solicitud:', atencion!.numSol!, scale),
              ],
            ),
            maxCardWidth,
          ),
          Padding(
            padding: EdgeInsets.only(bottom: 20 * scale),
            child: Text(
              'Volviendo en $_secondsRemaining s',
              style: TextStyle(
                fontSize: 18 * scale,
                fontStyle: FontStyle.italic,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

    // === Flujo con _insertResult (reserva online / práctico) ===
    // === Flujo con _insertResult (reserva online / práctico) ===
    if (_insertResult != null) {
      final res = _insertResult!;
      final ok = res.success;

      // ⬅️ Caso especial: PRÁCTICO con etapas pendientes
      if (!ok && _originalData is PracticoResult && res.extra is List) {
        _startTimer();
        final etapasList = (res.extra as List).cast<Map<String, dynamic>>();

        bool _pend(Map e) {
          final id = (e['EtapaId'] as num?)?.toInt() ?? 0;
          final r = (e['Resultado'] ?? '').toString();
          return id <= 885 && (r == 'E' || r == 'S');
        }

        final faltantes = etapasList.where(_pend).toList();

        const stepNames = {
          880: 'CAJA',
          881: 'FOTOGRAFÍA',
          882: 'EXAMEN PSICOMÉTRICO',
          883: 'EXAMEN SENSOMÉTRICO',
          884: 'ENTREVISTA MÉDICA',
          885: 'EXAMEN TEÓRICO',
        };

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                const AppHeader(),
                _centeredCard(
                  _resultCard(
                    icon: Icons.error_outline,
                    tone: Colors.red.shade700,
                    title: 'No puede continuar',
                    subtitle: 'Tiene etapas pendientes',
                    ticket: null,
                    scale: scale,
                    body: [
                      ...faltantes.map((e) {
                        final id = (e['EtapaId'] as num).toInt();
                        return _infoRow(
                          '$id  ${stepNames[id] ?? ''}',
                          '❌ Pendiente',
                          scale,
                          color: Colors.red,
                        );
                      }),
                    ],
                  ),
                  maxCardWidth,
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: 20 * scale),
                  child: Text(
                    'Volviendo en $_secondsRemaining s',
                    style: TextStyle(
                      fontSize: 18 * scale,
                      fontStyle: FontStyle.italic,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // ⬅️ Caso OK con datos originales (Reserva o PracticoResult)
      if (ok && _originalData != null) {
        if (_originalData is Reserva) {
          final obj = _originalData as Reserva;
          final tramite =
              (obj.clase2.isEmpty) ? 'Solicitud de Licencia' : obj.clase2;
          final clases = [
            obj.clase1,
            obj.clase2,
            obj.clase3,
            obj.clase4,
            obj.clase5,
            obj.clase6,
          ].where((c) => c.isNotEmpty).join(', ');

          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  const AppHeader(),
                  _centeredCard(
                    _resultCard(
                      icon: Icons.check_circle_outline,
                      tone: Colors.green.shade700,
                      title: 'Atención registrada, por favor espere su llamado',
                      subtitle: res.message ?? 'Por favor, espere su llamado',
                      ticket: res.ticket,
                      scale: scale,
                      body: [
                        _infoRow(
                          'Nombre:',
                          '${obj.nombres} ${obj.apellidos}',
                          scale,
                        ),
                        _infoRow('Trámite:', tramite, scale),
                        if (clases.isNotEmpty)
                          _infoRow('Clases:', clases, scale),
                        _infoRow(
                          'Fecha:',
                          formatearFecha(obj.fechaCitacion),
                          scale,
                        ),
                        _infoRow(
                          'Hora:',
                          obj.horaCitacion.substring(0, 5),
                          scale,
                        ),
                      ],
                    ),
                    maxCardWidth,
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: 20 * scale),
                    child: Text(
                      'Volviendo en $_secondsRemaining s',
                      style: TextStyle(
                        fontSize: 18 * scale,
                        fontStyle: FontStyle.italic,
                        color: Colors.black.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (_originalData is PracticoResult) {
          final obj = _originalData as PracticoResult;

          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  const AppHeader(),
                  _centeredCard(
                    _resultCard(
                      icon: Icons.check_circle_outline,
                      tone: Colors.green.shade700,
                      title: 'Atención registrada, por favor espere su llamado',
                      subtitle: 'Por favor, diríjase a la sala de espera',
                      ticket: _insertResult?.ticket,
                      scale: scale,
                      body: [
                        _infoRow('Nombre:', obj.nombre, scale),
                        const SizedBox(height: 12),
                        Text(
                          'Estado de etapas:',
                          style: TextStyle(
                            fontSize: 20 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...const {
                          880: 'CAJA',
                          881: 'FOTOGRAFÍA',
                          882: 'EXAMEN PSICOMÉTRICO',
                          883: 'EXAMEN SENSOMÉTRICO',
                          884: 'ENTREVISTA MÉDICA',
                          885: 'EXAMEN TEÓRICO',
                        }.entries.map((entry) {
                          // Nota: aquí usas etapasArg si llega por argumentos
                          final tienePend = etapasArg.any(
                            (e) =>
                                e.id == entry.key &&
                                (e.resultado == 'E' || e.resultado == 'S'),
                          );
                          return _infoRow(
                            '${entry.key}  ${entry.value}',
                            tienePend ? '❌ Pendiente' : '✔️ Completado',
                            scale,
                            color: tienePend ? Colors.red : Colors.green,
                          );
                        }),
                      ],
                    ),
                    maxCardWidth,
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: 20 * scale),
                    child: Text(
                      'Volviendo en $_secondsRemaining s',
                      style: TextStyle(
                        fontSize: 18 * scale,
                        fontStyle: FontStyle.italic,
                        color: Colors.black.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }

      // ⬅️ Resto: genérico
      final tone = ok ? Colors.green.shade700 : Colors.red.shade700;
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const AppHeader(),
              _centeredCard(
                _resultCard(
                  icon: ok ? Icons.check_circle_outline : Icons.error_outline,
                  tone: tone,
                  title: ok ? 'Atención registrada' : 'Error en registro',
                  subtitle:
                      res.message ??
                      (ok
                          ? 'Por favor, espere su llamado'
                          : 'No se pudo completar el registro'),
                  ticket: ok ? res.ticket : null,
                  scale: scale,
                  body: const [],
                ),
                maxCardWidth,
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 20 * scale),
                child: Text(
                  'Volviendo en $_secondsRemaining s',
                  style: TextStyle(
                    fontSize: 18 * scale,
                    fontStyle: FontStyle.italic,
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    /*── provider para mostrar datos base y disparar el insert ─*/
    final asyncData = ref.watch(reservaProvider(rut));

    return asyncData.when(
      loading:
          () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
      error:
          (err, _) => Scaffold(
            body: Center(child: Text('Error al cargar datos: $err')),
          ),
      data: (obj) {
        if (obj == null) {
          _startTimer();
          final isPractico = (flowArg == 'practico') || DatabaseConfig.practico;
          final subtitle =
              isPractico
                  ? 'No se encontraron datos de examen práctico para este RUT.'
                  : 'Este RUT no presenta horas tomadas para el día de hoy.';

          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  const AppHeader(),
                  _centeredCard(
                    _resultCard(
                      icon: Icons.info_outline,
                      tone: Colors.red.shade700,
                      title: 'Sin resultados',
                      subtitle: subtitle,
                      ticket: null,
                      scale: scale,
                      body: const [],
                    ),
                    maxCardWidth,
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: 20 * scale),
                    child: Text(
                      'Volviendo en $_secondsRemaining s',
                      style: TextStyle(
                        fontSize: 18 * scale,
                        fontStyle: FontStyle.italic,
                        color: Colors.black.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // LICENCIAS
        if (obj is Reserva) {
          int y = 0, m = 0, d = 0, hh = 0, mm = 0, ss = 0;
          try {
            y = int.parse(obj.fechaCitacion.substring(0, 4));
            m = int.parse(obj.fechaCitacion.substring(4, 6));
            d = int.parse(obj.fechaCitacion.substring(6, 8));
            final parts = obj.horaCitacion.split(':').map(int.parse).toList();
            hh = parts[0];
            mm = parts[1];
            ss = parts[2];
          } catch (_) {}
          final cita = DateTime(y, m, d, hh, mm, ss);
          final now = DateTime.now();

          final esMismoDia = (now.year == y && now.month == m && now.day == d);
          final soloFechaCita = DateTime(y, m, d);
          final soloFechaHoy = DateTime(now.year, now.month, now.day);
          final diffDias = soloFechaCita.difference(soloFechaHoy).inDays;

          final tramite =
              (obj.clase2.isEmpty) ? 'Solicitud de Licencia' : obj.clase2;
          final clases = [
            obj.clase1,
            obj.clase2,
            obj.clase3,
            obj.clase4,
            obj.clase5,
            obj.clase6,
          ].where((c) => c.isNotEmpty).join(', ');

          if (!esMismoDia) {
            _startTimer();
            final cuando =
                (diffDias == 1)
                    ? 'mañana'
                    : (diffDias == -1)
                    ? 'ayer'
                    : formatearFecha(obj.fechaCitacion);

            final rows = <Widget>[
              _infoRow('Nombre:', '${obj.nombres} ${obj.apellidos}', scale),
              _infoRow('Trámite:', tramite, scale),
              if (clases.isNotEmpty) _infoRow('Clases:', clases, scale),
              _infoRow(
                'Fecha:',
                (diffDias == 1 || diffDias == -1)
                    ? '${cuando[0].toUpperCase()}${cuando.substring(1)}'
                    : cuando,
                scale,
              ),
              _infoRow('Hora:', obj.horaCitacion.substring(0, 5), scale),
            ];

            return Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    const AppHeader(),
                    _centeredCard(
                      _resultCard(
                        icon: Icons.event_busy_rounded,
                        tone: Colors.orange.shade700,
                        title: 'Su hora no es para hoy',
                        subtitle:
                            (diffDias == 1)
                                ? 'Su cita es mañana a las ${obj.horaCitacion.substring(0, 5)}'
                                : (diffDias == -1)
                                ? 'Su cita fue ayer a las ${obj.horaCitacion.substring(0, 5)}'
                                : 'Su cita es el ${formatearFecha(obj.fechaCitacion)} a las ${obj.horaCitacion.substring(0, 5)}',
                        ticket: null,
                        scale: scale,
                        body: rows,
                      ),
                      maxCardWidth,
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: 20 * scale),
                      child: Text(
                        'Volviendo en $_secondsRemaining s',
                        style: TextStyle(
                          fontSize: 18 * scale,
                          fontStyle: FontStyle.italic,
                          color: Colors.black.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          _insertIfNeeded(rut: rut, obj: obj);
          _startTimer();

          final rows = <Widget>[
            _infoRow('Nombre:', '${obj.nombres} ${obj.apellidos}', scale),
            _infoRow('Trámite:', tramite, scale),
            if (clases.isNotEmpty) _infoRow('Clases:', clases, scale),
            _infoRow('Fecha:', formatearFecha(obj.fechaCitacion), scale),
            _infoRow('Hora:', obj.horaCitacion.substring(0, 5), scale),
          ];

          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  const AppHeader(),
                  _centeredCard(
                    _resultCard(
                      icon: Icons.person_outline,
                      tone: Colors.blue.shade700,
                      title: 'Información de citación',
                      subtitle: 'Por favor, espere su llamado',
                      ticket: null,
                      scale: scale,
                      body: rows,
                    ),
                    maxCardWidth,
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: 20 * scale),
                    child: Text(
                      'Volviendo en $_secondsRemaining s',
                      style: TextStyle(
                        fontSize: 18 * scale,
                        fontStyle: FontStyle.italic,
                        color: Colors.black.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // PRÁCTICO (modo proveedor)
        if (obj is PracticoResult) {
          _insertIfNeeded(rut: rut, obj: obj);
          _startTimer();

          final rows = <Widget>[
            _infoRow('Nombre:', obj.nombre, scale),
            SizedBox(height: 12 * scale),
            Text(
              'Estado de etapas:',
              style: TextStyle(
                fontSize: 20 * scale,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 6 * scale),
          ];

          for (final entry
              in const {
                880: 'CAJA',
                881: 'FOTOGRAFÍA',
                882: 'EXAMEN PSICOMÉTRICO',
                883: 'EXAMEN SENSOMÉTRICO',
                884: 'ENTREVISTA MÉDICA',
                885: 'EXAMEN TEÓRICO',
              }.entries) {
            final tienePend = etapasArg.any(
              (e) =>
                  e.id == entry.key &&
                  (e.resultado == 'E' || e.resultado == 'S'),
            );
            rows.add(
              _infoRow(
                '${entry.key}  ${entry.value}',
                tienePend ? '❌ Pendiente' : '✔️ Completado',
                scale,
                color: tienePend ? Colors.red : Colors.green,
              ),
            );
          }

          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  const AppHeader(),
                  _centeredCard(
                    _resultCard(
                      icon: Icons.person_outline,
                      tone: Colors.blue.shade700,
                      title: 'Examen práctico',
                      subtitle: 'Por favor, diríjase a la sala de espera',
                      ticket: null,
                      scale: scale,
                      body: rows,
                    ),
                    maxCardWidth,
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: 20 * scale),
                    child: Text(
                      'Volviendo en $_secondsRemaining s',
                      style: TextStyle(
                        fontSize: 18 * scale,
                        fontStyle: FontStyle.italic,
                        color: Colors.black.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return const Scaffold(
          body: Center(child: Text('No se encontraron datos.')),
        );
      },
    );
  }
}

/*── Mini extensión para oscurecer tonos en el chip ─*/
extension on Color {
  Color darken([double amount = .2]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }

}
