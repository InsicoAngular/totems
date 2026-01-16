// lib/printing/raw_escpos.dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'package:image/image.dart' as img;

import '../models/reserva.dart';
import '../models/practico_result.dart';
import '../models/atencion.dart';
import 'print_config.dart';

import 'package:flutter/services.dart' show rootBundle; // 👈 para assets
import 'dart:typed_data';

/// Envío ESC/POS por RAW al spooler de Windows.
class EscPosRawPrinter {
  final String printerName;
  final int codepage;

  EscPosRawPrinter({String? printerName, int? codepage})
    : printerName = printerName ?? PrintConfig.printerNameLicencias,
      codepage = codepage ?? PrintConfig.codepage;

  // ── ESC/POS ─────────────────────────────────────────────
  static const _init = [0x1B, 0x40]; // ESC @
  static const _intlLatin = [0x1B, 0x52, 0x0C]; // ESC R 12 (LatAm)
  static const _alignL = [0x1B, 0x61, 0x00];
  static const _alignC = [0x1B, 0x61, 0x01];
  static const _boldOn = [0x1B, 0x45, 0x01];
  static const _boldOff = [0x1B, 0x45, 0x00];
  static const _cutFull = [0x1D, 0x56, 0x00]; // GS V 0 (corte total)

  List<int> _feedN(int n) {
    final v = (n < 1) ? 1 : (n > 8 ? 8 : n);
    return [0x1B, 0x64, v];
  }

  List<int> _sizeWH(int w, int h) {
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    if (w > 8) w = 8;
    if (h > 8) h = 8;
    final n = ((w - 1) << 4) | (h - 1);
    return [0x1D, 0x21, n];
  }

  List<int> _enc(String s) => latin1.encode(s);

  void _line(
    BytesBuilder b,
    String s, {
    bool center = false,
    bool bold = false,
    int w = 1,
    int h = 2,
  }) {
    b
      ..add(center ? _alignC : _alignL)
      ..add(bold ? _boldOn : _boldOff)
      ..add(_sizeWH(w, h))
      ..add(_enc('$s\n'))
      ..add(_sizeWH(1, 1));
  }

  // Empaqueta una imagen 1-bit en formato raster ESC/POS (GS v 0)
  void _addRasterImage(BytesBuilder b, List<int> mono, int width, int height) {
    final bytesPerRow = (width + 7) >> 3;
    final xL = bytesPerRow & 0xFF;
    final xH = (bytesPerRow >> 8) & 0xFF;
    final yL = height & 0xFF;
    final yH = (height >> 8) & 0xFF;
    b.add([0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH]); // GS v 0 m=0
    b.add(mono);
  }

  // Convierte Image a 1-bit con Atkinson dithering (o umbral simple)
  List<int> _toMonoBytes(
    img.Image g, {
    bool dither = true,
    int bias = 28,
    int minTh = 150,
    int maxTh = 210,
  }) {
    final w = g.width, h = g.height;
    final bytesPerRow = (w + 7) >> 3;
    final out = List<int>.filled(bytesPerRow * h, 0);

    // Luma y umbral dinámico
    final lumin = List<double>.filled(w * h, 0);
    double sum = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final px = g.getPixel(x, y);
        final r = px.r.toDouble();
        final gg = px.g.toDouble();
        final b = px.b.toDouble();
        final yy = 0.299 * r + 0.587 * gg + 0.114 * b; // 0..255
        lumin[y * w + x] = yy;
        sum += yy;
      }
    }
    int th =
        (sum / (w * h)).round() + bias; // umbral más alto => imagen más clara
    th = th.clamp(minTh, maxTh);

    // Atkinson error diffusion
    if (dither) {
      final err = List<double>.filled(w * h, 0);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final idx = y * w + x;
          final old = (lumin[idx] + err[idx]).clamp(0, 255);
          final newV = (old >= th) ? 255.0 : 0.0; // 255 blanco, 0 negro
          final qerr = (old - newV) / 8.0;

          // Escribe bit
          final byteIndex = y * bytesPerRow + (x >> 3);
          final bit = 7 - (x & 7); // MSB primero
          if (newV == 0.0) out[byteIndex] |= (1 << bit); // 1 = punto negro

          // Distribuye error (Atkinson)
          if (x + 1 < w) err[idx + 1] += qerr;
          if (x + 2 < w) err[idx + 2] += qerr;
          if (y + 1 < h) {
            if (x > 0) err[idx + w - 1] += qerr;
            err[idx + w] += qerr;
            if (x + 1 < w) err[idx + w + 1] += qerr;
          }
          if (y + 2 < h) err[idx + 2 * w] += qerr;
        }
      }
    } else {
      // Umbral simple
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final v = lumin[y * w + x];
          final byteIndex = y * bytesPerRow + (x >> 3);
          final bit = 7 - (x & 7);
          if (v < th) out[byteIndex] |= (1 << bit);
        }
      }
    }
    return out;
  }

  // Carga, centra, aplana sobre blanco, redimensiona y añade al buffer como raster.
  Future<void> _addLogoFromPath(
    BytesBuilder b,
    String path, {
    int maxWidth = 512,
    bool dither = true,
    int bias = 28,
  }) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return;

      final bytes = await file.readAsBytes();
      final src = img.decodeImage(bytes);
      if (src == null) return;

      // 1) Redimensiona (mantiene aspecto)
      final targetW = math.min(maxWidth, src.width);
      var work = img.copyResize(
        src,
        width: targetW,
        interpolation: img.Interpolation.average,
      );

      // 2) Aplana sobre blanco si trae alpha
      final bg = img.Image(width: work.width, height: work.height);
      img.fill(bg, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(bg, work, dstX: 0, dstY: 0);
      work = bg;

      // 3) Escala a grises
      final gray = img.grayscale(work);

      // 4) Mono 1-bit
      final mono = _toMonoBytes(gray, dither: dither, bias: bias);

      // Centrar
      b.add(_alignC);

      // 5) Comando raster (GS v 0)
      _addRasterImage(b, mono, gray.width, gray.height);

      // Feed debajo del logo
      b.add(_feedN(1));
    } catch (_) {
      // Silencioso
    }
  }

  Future<void> _addLogoIfAvailable(BytesBuilder b) async {
    final path = (PrintConfig.logoPath).trim();
    if (path.isEmpty) return;
    await _addLogoFromPath(b, path, maxWidth: 512, dither: true, bias: 30);
  }

  // ── IMPRESIONES ─────────────────────────────────────────

  /// ONLINE: trae reserva y emite comprobante. Incluye TICKET si viene (>0).
  Future<void> printReserva(
    Reserva r, {
    required String fechaFormateada,
    int? correlativoDia, // 👈 nuevo
  }) async {
    final b =
        BytesBuilder()
          ..add(_init)
          ..add([0x1B, 0x74, codepage])
          ..add(_intlLatin)
          ..add(_alignC);

    await _addLogoIfAvailable(b);

    _line(b, '', center: true, bold: true, w: 2, h: 2);
    _line(b, 'MUNICIPALIDAD', center: true, bold: true, w: 2, h: 2);
    _line(b, 'DE PUENTE ALTO', center: true, bold: true, w: 2, h: 2);
    b.add(_feedN(2));

    final nombre = ('${r.nombres} ${r.apellidos}').toUpperCase();
    _line(b, nombre, center: true, bold: true, w: 2, h: 2);
    b.add(_feedN(1));

    // 👇 NUEVO: correlativo del día (si viene)
    if ((correlativoDia ?? 0) > 0) {
      _line(
        b,
        'Correlativo del día: $correlativoDia',
        center: true,
        w: 1,
        h: 2,
      );
      b.add(_feedN(1));
    }

    final tramite = r.clase2.isEmpty ? 'Solicitud de Licencia' : r.clase2;
    final clases = [
      r.clase1,
      r.clase2,
      r.clase3,
      r.clase4,
      r.clase5,
      r.clase6,
    ].where((c) => c.isNotEmpty).join(', ');

    _line(b, 'RUT: ${r.numRut}', center: true, w: 1, h: 2);
    _line(b, 'Tramite: $tramite', center: true, w: 1, h: 2);
    if (clases.isNotEmpty)
      _line(b, 'Clases: $clases', center: true, w: 1, h: 2);
    _line(b, 'Fecha: $fechaFormateada', center: true, w: 1, h: 2);
    _line(
      b,
      'Hora: ${r.horaCitacion.substring(0, 5)}',
      center: true,
      w: 1,
      h: 2,
    );

    b
      ..add(_feedN(2))
      ..add(_alignC)
      ..add(_sizeWH(1, 2))
      ..add(_enc('Por favor, espere su llamado\n'))
      ..add(_sizeWH(1, 1))
      ..add(_feedN(5))
      ..add(_cutFull);

    await _send(b.toBytes());
  }

  /// Práctico genérico (sin número gigante). Incluye logo.
  Future<void> printPractico(PracticoResult p) async {
    final b =
        BytesBuilder()
          ..add(_init)
          ..add([0x1B, 0x74, codepage])
          ..add(_intlLatin)
          ..add(_alignC);

    await _addLogoIfAvailable(b);

    _line(b, 'EXAMEN PRÁCTICO', center: true, bold: true, w: 2, h: 3);
    b.add(_feedN(1));
    _line(b, p.nombre.toUpperCase(), center: true, bold: true, w: 1, h: 2);
    b.add(_feedN(1));
    _line(b, 'Espere su llamado', center: true, w: 1, h: 2);
    _line(b, 'por pantalla', center: true, w: 1, h: 2);

    b
      ..add(_feedN(5))
      ..add(_cutFull);

    await _send(b.toBytes());
  }

  Future<String> _pickLicPrinter() async {
    final installed = EscPosRawPrinter.listInstalledPrinters();
    final pref = PrintConfig.printerNameLicencias;
    if (installed.contains(pref)) return pref;

    // usa la misma que sí probaste (práctico)
    final fallback = PrintConfig.printerNamePractico;
    if (installed.contains(fallback)) return fallback;

    // último recurso: primera disponible
    if (installed.isNotEmpty) return installed.first;

    return pref;
  }

  Future<void> printAlcAtencion(Atencion a, {required int ticket}) async {
    // === helpers locales ===
    String _fmtFecha(String s) {
      final t = s.trim();
      if (t.isEmpty) return '';
      if (RegExp(r'^\d{8}$').hasMatch(t)) {
        return '${t.substring(6, 8)}/${t.substring(4, 6)}/${t.substring(0, 4)}';
      }
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t)) {
        final p = t.split('-');
        return '${p[2]}/${p[1]}/${p[0]}';
      }
      return t;
    }

    String _fmtHora(String s) {
      final t = s.trim();
      if (t.isEmpty) return '';
      return t.length >= 5 ? t.substring(0, 5) : t;
    }

    String _dv(String body) {
      int sum = 0, mul = 2;
      for (int i = body.length - 1; i >= 0; i--) {
        sum += int.parse(body[i]) * mul;
        mul = (mul == 7) ? 2 : mul + 1;
      }
      final res = 11 - (sum % 11);
      if (res == 11) return '0';
      if (res == 10) return 'K';
      return res.toString();
    }

    String _rutBonito(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return t;
      if (t.contains('-')) return t;
      final body = t.replaceAll(RegExp(r'\D'), '');
      if (body.isEmpty) return t;
      return '$body-${_dv(body)}';
    }

    // ✅ Resolver SIEMPRE desde la atención (nunca usar ticket/id)
    String _numeroDelDia() {
      final c1 = (a.correlativo1 ?? '').trim();
      if (c1.isNotEmpty) return c1;
      final c0 = (a.correlativo ?? '').trim();
      if (c0.isNotEmpty) return c0;
      return ''; // sin número (no caer a id/numSol)
    }

    final now = DateTime.now();
    final nowFecha =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final nowHora =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final b =
        BytesBuilder()
          ..add(_init)
          ..add([0x1B, 0x74, codepage])
          ..add(_intlLatin)
          ..add(_alignC);

    try {
      await _addLogoIfAvailable(b);
    } catch (_) {}

    // Encabezado
    _line(b, '', center: true, bold: true, w: 2, h: 2);
    _line(b, 'MUNICIPALIDAD', center: true, bold: true, w: 2, h: 2);
    _line(b, 'DE PUENTE ALTO', center: true, bold: true, w: 2, h: 2);
    _line(b, 'COMPROBANTE DE ATENCION', center: true, bold: true, w: 1, h: 2);
    _line(b, '', center: true, bold: true, w: 2, h: 2);

    // N° gigante del ticket
    _line(b, 'TICKET', center: true, bold: true, w: 2, h: 3);
    _line(b, 'Nº $ticket', center: true, bold: true, w: 3, h: 3);

    b.add(_feedN(1));

    // ✅ Número grande del día (si existe)
    final numeroDia = _numeroDelDia();
    if (numeroDia.isNotEmpty) {
      _line(b, 'Nº $numeroDia', center: true, bold: true, w: 3, h: 3);
      b.add(_feedN(1));

      // 👇 adicional: correlativo chiquito bajo el número grande
      _line(b, 'Correlativo del día: $numeroDia', center: true, w: 1, h: 2);
      b.add(_feedN(1));
    }

    // Título con nombre (o RUT si no hay nombre)
    final nombre = ('${a.nombres ?? ''} ${a.apellidos ?? ''}').trim();
    final title =
        nombre.isNotEmpty
            ? nombre.toUpperCase()
            : (a.numRut.trim().isNotEmpty
                ? 'RUT ${_rutBonito(a.numRut)}'
                : 'ATENCION');
    _line(b, title, center: true, bold: true, w: 1, h: 2);
    b.add(_feedN(1));

    // Detalles
    final fechaPrint =
        a.fecha.trim().isNotEmpty ? _fmtFecha(a.fecha) : nowFecha;
    final horaPrint =
        ((a.hora ?? '').trim().isNotEmpty) ? _fmtHora(a.hora!) : nowHora;

    _line(b, 'Fecha: $fechaPrint', center: true, w: 1, h: 2);
    if (horaPrint.isNotEmpty)
      _line(b, 'Hora: $horaPrint', center: true, w: 1, h: 2);
    if (a.tipo.trim().isNotEmpty)
      _line(b, 'Trámite: ${a.tipo}', center: true, w: 1, h: 2);

    if (a.numRut.trim().isNotEmpty) {
      _line(b, 'RUT: ${_rutBonito(a.numRut)}', center: true, w: 1, h: 2);
    }
    if ((a.numSol ?? '').trim().isNotEmpty) {
      _line(b, 'N° Solicitud: ${a.numSol}', center: true, w: 1, h: 2);
    }

    // Linea informativa adicional (pequeña) con correlativo, si quieres
    if ((a.correlativo1 ?? '').trim().isNotEmpty) {
      _line(b, 'Correlativo: ${a.correlativo1}', center: true, w: 1, h: 1);
    } else if ((a.correlativo ?? '').trim().isNotEmpty) {
      _line(b, 'Correlativo: ${a.correlativo}', center: true, w: 1, h: 1);
    }

    b
      ..add(_feedN(2))
      ..add(_alignC)
      ..add(_sizeWH(1, 2))
      ..add(_enc('Por favor, espere su llamado\n'))
      ..add(_sizeWH(1, 1))
      ..add(_feedN(5))
      ..add(_cutFull);

    await _send(b.toBytes());
  }

  /// Ticket simple de Examen Práctico con N° gigante, nombre y logo.
  Future<void> printPracticoTicket({
    required String nombre,
    required int ticket,
  }) async {
    final b =
        BytesBuilder()
          ..add(_init)
          ..add([0x1B, 0x74, codepage])
          ..add(_intlLatin)
          ..add(_alignC);

    await _addLogoIfAvailable(b);

    _line(b, '', center: true, bold: true, w: 2, h: 3);
    _line(b, 'EXAMEN PRÁCTICO', center: true, bold: true, w: 2, h: 3);
    b.add(_feedN(1));

    // Número MUY grande
    _line(b, 'Nº $ticket', center: true, bold: true, w: 3, h: 3);
    b.add(_feedN(1));

    // Nombre
    if (nombre.trim().isNotEmpty) {
      _line(b, nombre.toUpperCase(), center: true, bold: true, w: 1, h: 2);
      b.add(_feedN(1));
    }

    _line(b, 'Preséntese con este número', center: true, w: 1, h: 2);

    b
      ..add(_feedN(5))
      ..add(_cutFull);

    await _send(b.toBytes());
  }

  /// Lista las colas instaladas (útil para validar el nombre exacto).
  static List<String> listInstalledPrinters() {
    final flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
    final pcbNeeded = calloc<DWORD>();
    final pcReturned = calloc<DWORD>();
    // Primera llamada para tamaño
    EnumPrinters(flags, nullptr, 4, nullptr, 0, pcbNeeded, pcReturned);
    final needed = pcbNeeded.value;
    final names = <String>[];

    if (needed > 0) {
      final buf = calloc<BYTE>(needed);
      final ok = EnumPrinters(
        flags,
        nullptr,
        4,
        buf.cast(),
        needed,
        pcbNeeded,
        pcReturned,
      );
      if (ok != 0) {
        final count = pcReturned.value;
        final size = sizeOf<PRINTER_INFO_4>();
        for (var i = 0; i < count; i++) {
          final info =
              Pointer<PRINTER_INFO_4>.fromAddress(buf.address + i * size).ref;
          names.add(info.pPrinterName.toDartString());
        }
      }
      calloc.free(buf);
    }

    calloc
      ..free(pcbNeeded)
      ..free(pcReturned);

    return names;
  }

  /// Envía un ticket de prueba para validar corte/salida en una cola.
  static Future<String?> quickTest(String printerName) async {
    try {
      final p = EscPosRawPrinter(printerName: printerName);
      final b =
          BytesBuilder()
            ..add(_init)
            ..add([0x1B, 0x74, PrintConfig.codepage])
            ..add(_intlLatin);
      p._line(b, 'PRUEBA ESC/POS', center: true, bold: true, w: 2, h: 2);
      b
        ..add(p._feedN(2))
        ..add(_cutFull);
      await p._send(b.toBytes());
      return null; // ok
    } catch (e) {
      return e.toString();
    }
  }

  // ── Spooler RAW (Win32) ─────────────────────────────────
  Future<void> _send(List<int> bytes) async {
    final hPrinter = calloc<HANDLE>();
    final pName = printerName.toNativeUtf16();
    final opened = OpenPrinter(pName, hPrinter, nullptr);
    calloc.free(pName);
    if (opened == 0) {
      final err = GetLastError();
      calloc.free(hPrinter);
      throw WindowsException(HRESULT_FROM_WIN32(err));
    }

    final di = calloc<DOC_INFO_1>();
    di.ref
      ..pDocName = 'Flutter ESC/POS'.toNativeUtf16()
      ..pOutputFile = nullptr
      ..pDatatype = 'RAW'.toNativeUtf16();

    if (StartDocPrinter(hPrinter.value, 1, di.cast()) == 0) {
      final err = GetLastError();
      ClosePrinter(hPrinter.value);
      calloc
        ..free(di.ref.pDocName)
        ..free(di.ref.pDatatype)
        ..free(di);
      calloc.free(hPrinter);
      throw WindowsException(HRESULT_FROM_WIN32(err));
    }

    StartPagePrinter(hPrinter.value);

    final dataPtr = calloc<Uint8>(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      dataPtr[i] = bytes[i];
    }
    final written = calloc<DWORD>();
    final ok = WritePrinter(
      hPrinter.value,
      dataPtr.cast(),
      bytes.length,
      written,
    );

    EndPagePrinter(hPrinter.value);
    EndDocPrinter(hPrinter.value);
    ClosePrinter(hPrinter.value);

    calloc
      ..free(dataPtr)
      ..free(written)
      ..free(di.ref.pDocName)
      ..free(di.ref.pDatatype)
      ..free(di);

    if (ok == 0) {
      final err = GetLastError();
      throw WindowsException(HRESULT_FROM_WIN32(err));
    }
  }
}
