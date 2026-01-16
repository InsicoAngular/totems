import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_service.dart';
import '../printing/raw_escpos.dart';
import '../printing/print_config.dart';

class PracticoOperatorScreen extends StatefulWidget {
  const PracticoOperatorScreen({super.key});

  @override
  State<PracticoOperatorScreen> createState() => _PracticoOperatorScreenState();
}

class _PracticoOperatorScreenState extends State<PracticoOperatorScreen> {
  final _rutCtl = TextEditingController();
  final _scrollCtl = ScrollController();

  // Data/paginación
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  final int _pageSize = 50;
  final int _daysBack = 3;

  List<Map<String, dynamic>> _rows = [];

  // Impresoras
  List<String> _printers = [];
  String? _printerSel;

  @override
  void initState() {
    super.initState();
    _initPrinters();
    _load(reset: true);
    _scrollCtl.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    _rutCtl.dispose();
    super.dispose();
  }

  Future<void> _initPrinters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved =
          prefs.getString('printerPractico') ?? PrintConfig.printerNamePractico;

      final list = EscPosRawPrinter.listInstalledPrinters();
      setState(() {
        _printers = list;
        _printerSel =
            list.contains(saved)
                ? saved
                : (list.isNotEmpty ? list.first : null);
      });
    } catch (_) {
      // no printers? dejar nulo
    }
  }

  Future<void> _savePrinterSel(String? v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printerPractico', v ?? '');
  }

  // Helpers
  String _fmtRut(String raw) {
    final c = raw.toUpperCase().replaceAll(RegExp(r'[^0-9K]'), '');
    if (c.length < 2) return raw;
    return '${c.substring(0, c.length - 1)}-${c.substring(c.length - 1)}';
  }

  String _etapaName(int id) {
    switch (id) {
      case 880:
        return 'CAJA';
      case 881:
        return 'FOTOGRAFÍA';
      case 882:
        return 'PSICOMÉTRICO';
      case 883:
        return 'SENSOMÉTRICO';
      case 884:
        return 'ENTREVISTA MÉDICA';
      case 885:
        return 'EXAMEN TEÓRICO';
      default:
        return 'ETAPA $id';
    }
  }

  // Data
  Future<void> _load({bool reset = false}) async {
    final rutFilter =
        _rutCtl.text.trim().isEmpty ? null : _fmtRut(_rutCtl.text);

    if (reset) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _hasMore = true;
        _page = 0;
        _rows.clear();
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final list = await DatabaseService.instance.practicoPendientes(
        rutFilter: rutFilter,
        limit: _pageSize,
        daysBack: _daysBack,
        onlyReady:
            true, // sin RUT → sólo aptos; con RUT esto se ignora en backend
      );

      setState(() {
        if (reset) {
          _rows = list;
        } else {
          _rows.addAll(list);
        }
        _hasMore = list.length == _pageSize && rutFilter == null;
        if (_hasMore) _page += 1;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _maybeLoadMore() {
    if (_scrollCtl.position.pixels >=
        _scrollCtl.position.maxScrollExtent * 0.9) {
      _load(reset: false);
    }
  }

  Future<void> _buscar() => _load(reset: true);

  // Print
 // Print
Future<void> _confirmAndPrint(Map<String, dynamic> row) async {
  final nombre = (row['nombre'] ?? '').toString();
  final rut = (row['rut'] ?? '').toString();
  final pend = (row['pendCount'] as int?) ?? 0;
  final faltaId = (row['menorEtapaPendiente'] as int?) ?? 0;

  if (pend > 0) {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No apto para imprimir'),
        content: Text('Falta: ${_etapaName(faltaId)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    return;
  }

  // 👇 Paso nuevo: elegir tipo de cupo
  final label = await showDialog<String>(
    context: context,
    builder: (_) => SimpleDialog(
      title: const Text('Seleccione el cupo a utilizar'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'Examenes Practicos'),
          child: const Text('Práctico B'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'Examenes Practicos C y CR'),
          child: const Text('Práctico C y CR'),
        ),
      ],
    ),
  );

  if (label == null) return;

  // Verificamos disponibilidad del cupo elegido
  final cupo = await DatabaseService.instance.checkCupoManualPorLabel(
    labelTramite: label,
    requiereApertura: false,
  );
  if (!cupo.ok || cupo.cupoId == null) {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sin cupos disponibles'),
        content: Text(cupo.motivo),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
    return;
  }

  // Confirmación
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('¿Desea emitir el ticket?'),
      content: Text('$nombre\n$rut\n\nCupo seleccionado: $label'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Continuar'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  try {
    // Registrar usando el botón elegido
    final res = await DatabaseService.instance.registrarManualSmart(
      rut: rut,
      tipo: 'T', // mantienes el mismo tipo interno para impresión/prioridad
      cupoId: cupo.cupoId,
    );

    if (!res.success || (res.ticket ?? 0) <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'No se pudo emitir')),
      );
      return;
    }

    // Vista previa
    final printerName = _printerSel ?? PrintConfig.printerNamePractico;
    final wantPrint = await _showPrintPreviewDialog(
      nombre: nombre,
      ticket: res.ticket!,
      impresora: printerName,
    );

    if (wantPrint != true) return;

    // ── POST crear al endpoint (JSON exacto)
final ep = await DatabaseService.instance.crearPracticoTabletWithReason(
  rutFormateado: rut,
  labelTramite: label,
  fechaExamen: DateTime.now(),
);

if (!ep.ok) {
  if (!mounted) return;
  final detalle = [
    if (ep.status > 0) 'HTTP ${ep.status}',
    if ((ep.message ?? '').isNotEmpty) ep.message,
    if ((ep.body ?? '').isNotEmpty) 'Body: ${ep.body}',
  ].whereType<String>().join(' · ');

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('No se pudo insertar en el endpoint. $detalle')),
  );

  // Si quieres abortar la impresión si falla el POST:
  // return;
}

    // Imprimir
    final p = EscPosRawPrinter(
      printerName: printerName,
      codepage: PrintConfig.codepage,
    );
    await p.printPracticoTicket(nombre: nombre, ticket: res.ticket!);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ticket #${res.ticket} emitido en "$printerName"'),
      ),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error al imprimir: $e')),
    );
  }
}


  Future<void> _probarImpresora() async {
    final cola = _printerSel ?? PrintConfig.printerNamePractico;
    final err = await EscPosRawPrinter.quickTest(cola);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err == null ? 'Prueba enviada a "$cola"' : 'QuickTest falló: $err',
        ),
      ),
    );
  }

  Future<int?> _checkCupoAntesDeImprimir() async {
    try {
      final cupo = await DatabaseService.instance.checkCupoPracticoCombinado();

      if (!cupo.ok) {
        // Aviso bloqueante: no seguimos
        await showDialog<void>(
          context: context,
          builder:
              (_) => AlertDialog(
                title: const Text('Sin cupos disponibles'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cupo.motivo),
                    const SizedBox(height: 6),
                    if (cupo.horaInicio != '00:00:00' &&
                        cupo.horaTermino != '00:00:00')
                      Text(
                        'Horario: ${cupo.horaInicio.substring(0, 5)} – ${cupo.horaTermino.substring(0, 5)}',
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Disponibles: ${cupo.disponibles < 0 ? 0 : cupo.disponibles}',
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Entendido'),
                  ),
                ],
              ),
        );
        return null;
      }

      // OK: devolvemos el cupoId del bloque ideal para consumir
      return cupo.cupoId;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error verificando cupos: $e')));
      return null;
    }
  }

  // --- PREVIEW ----------------------------------------------

  Future<bool?> _showPrintPreviewDialog({
    required String nombre,
    required int ticket,
    required String impresora,
  }) {
    final cs = Theme.of(context).colorScheme;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text('Vista previa de impresión'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Tarjeta de “comprobante” simulada (80mm aprox.)
                Container(
                  width: 320, // ~80mm a ~240-320px depende densidad
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'MUNICIPALIDAD',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        'DE PUENTE ALTO',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'EXAMEN PRÁCTICO',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: cs.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      // Nº grande
                      Text(
                        'Nº $ticket',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 40,
                          height: 1.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      // Nombre
                      if (nombre.trim().isNotEmpty)
                        Text(
                          nombre.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      const SizedBox(height: 20),
                      const Text(
                        'Preséntese con este número',
                        style: TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Divider(color: cs.outlineVariant),
                      const SizedBox(height: 8),
                      // Pie, como en el raw_escpos (mensajito)
                      const Text(
                        'Por favor, espere su llamado',
                        style: TextStyle(fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.print_outlined, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Impresora: $impresora',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.local_printshop),
              label: const Text('Imprimir'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Examen Práctico'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Buscador + impresora
            Container(
              margin: const EdgeInsets.all(16),
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Búsqueda y Configuración',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _rutCtl,
                              decoration: InputDecoration(
                                labelText: 'Buscar por RUT',
                                hintText: 'Ej: 12345678-9',
                                prefixIcon: const Icon(Icons.search),
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: cs.surface,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9kK\-\.]'),
                                ),
                              ],
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _buscar(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _loading ? null : _buscar,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                            icon:
                                _loading
                                    ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cs.onPrimary,
                                      ),
                                    )
                                    : const Icon(Icons.search),
                            label: const Text('Buscar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value:
                                  _printers.contains(_printerSel)
                                      ? _printerSel
                                      : null,
                              items:
                                  _printers
                                      .map(
                                        (p) => DropdownMenuItem(
                                          value: p,
                                          child: Text(p),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (v) async {
                                setState(() => _printerSel = v);
                                await _savePrinterSel(v);
                              },
                              decoration: InputDecoration(
                                labelText: 'Impresora práctica',
                                prefixIcon: const Icon(Icons.print),
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: cs.surface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _probarImpresora,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Probar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Lista (pull-to-refresh + infinite scroll)
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: ListView.separated(
                  controller: _scrollCtl,
                  itemCount: _rows.length + (_loadingMore ? 1 : 0),
                  separatorBuilder:
                      (_, __) => Divider(height: 1, color: cs.outlineVariant),
                  itemBuilder: (_, i) {
                    if (_loadingMore && i == _rows.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final r = _rows[i];
                    final nombre = (r['nombre'] ?? '').toString();
                    final rut = (r['rut'] ?? '').toString();
                    final pend = (r['pendCount'] as int?) ?? 0;
                    final etapaId = (r['menorEtapaPendiente'] as int?) ?? 0;

                    final trailing =
                        (pend > 0)
                            ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Falta: ${_etapaName(etapaId)}',
                                style: TextStyle(
                                  color: cs.onErrorContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                            : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Apto para práctico',
                                style: TextStyle(
                                  color: cs.onSecondaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );

                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(
                        nombre.isEmpty ? '—' : nombre,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(rut),
                      trailing: trailing,
                      onTap: () => _confirmAndPrint(r),
                    );
                  },
                ),
              ),
            ),

            if (_rows.isEmpty && !_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text('Sin personas (aptos o coincidentes por RUT)'),
              ),
          ],
        ),
      ),
    );
  }
}
