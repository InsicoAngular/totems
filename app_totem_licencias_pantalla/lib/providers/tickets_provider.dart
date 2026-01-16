// lib/providers/tickets_provider.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/database_config.dart';
import '../models/ticket.dart';

String _normalizeWsUrl(String url) {
  url = url.trim();
  if (url.endsWith('#')) url = url.substring(0, url.length - 1);
  if (url.startsWith('http://'))  return 'ws://${url.substring(7)}';
  if (url.startsWith('https://')) return 'wss://${url.substring(8)}';
  return url;
}

String _apiBaseFromWs(String wsUrl) {
  if (wsUrl.startsWith('wss://')) return 'https://${wsUrl.substring(6)}';
  if (wsUrl.startsWith('ws://'))  return 'http://${wsUrl.substring(5)}';
  return wsUrl.replaceFirst('/ws', '');
}

/// Stream de tickets (turno actual + historial) resiliente:
/// - Conecta por WS
/// - Reintenta con backoff exponencial
/// - Ignora ping "🫀"
/// - Mientras el WS no vuelve, hace fallback a REST /api/llamados/estado
final ticketsStreamProvider = StreamProvider.autoDispose<List<Ticket>>((ref) async* {
  // Emitimos algo altiro para sacar el loading
  yield const <Ticket>[];

  final prefs = await SharedPreferences.getInstance();

  // 1) URL efectiva del WS
  final prefUrl = prefs.getString('wsUrl')?.trim();
  final rawUrl  = (prefUrl == null || prefUrl.isEmpty) ? DatabaseConfig.wsUrl : prefUrl;
  final wsUrl   = _normalizeWsUrl(rawUrl);
  final apiBase = _apiBaseFromWs(wsUrl);

  // 2) Filtros opcionales (si no, backend usa appsettings)
  final tiposRaw    = (prefs.getString('tipoEspera') ?? '').trim().toUpperCase();
  final familiesRaw = (prefs.getString('families') ?? '').trim().toUpperCase();
  final topPref     = prefs.getInt('topPerTipo') ?? 3;

  final types = (tiposRaw.isEmpty || tiposRaw == '*')
      ? const <String>[]
      : tiposRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  final families = familiesRaw.isEmpty
      ? const <String>[]
      : familiesRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  // 3) Estado local y emisor
  final byId = <int, Ticket>{};
  final controller = StreamController<List<Ticket>>(sync: true);
  void emit() {
    final list = byId.values.toList()..sort((a, b) => b.id.compareTo(a.id));
    controller.add(list.take(10).toList());
  }

  // Mantener con vida si hay listeners
  final link = ref.keepAlive();
  var disposed = false;
  ref.onDispose(() async {
    disposed = true;
    link.close();
    await controller.close();
  });

  // 4) REST fallback
  final dio = Dio(BaseOptions(
    baseUrl: apiBase,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  Future<void> syncByRest() async {
    try {
      final r = await dio.get('/api/llamados/estado', queryParameters: {'ultimos': 3});
      final data = r.data as Map<String, dynamic>;

      if (data['actual'] != null) {
        final m = Map<String, dynamic>.from(data['actual']);
        final t = Ticket(
          id: int.tryParse('${m['id'] ?? 0}') ?? 0,
          name: (m['name'] ?? m['nombre'] ?? '').toString(),
          station: (m['station'] ?? m['modulo'] ?? '').toString(),
          isManual: (m['isManual'] == true || m['EsManual'] == 1),
          tipoEspera: (m['tipoEspera'] ?? '').toString(),
        );
        if (t.id > 0) byId[t.id] = t;
      }

      if (data['historial'] is List) {
        for (final e in (data['historial'] as List)) {
          final m = Map<String, dynamic>.from(e);
          final t = Ticket(
            id: int.tryParse('${m['id'] ?? 0}') ?? 0,
            name: (m['name'] ?? m['nombre'] ?? '').toString(),
            station: (m['station'] ?? m['modulo'] ?? '').toString(),
            isManual: (m['isManual'] == true || m['EsManual'] == 1),
            tipoEspera: (m['tipoEspera'] ?? '').toString(),
          );
          if (t.id > 0) byId[t.id] = t;
        }
      }
      emit();
    } catch (_) { /* silencio */ }
  }

  // 5) Conexión WS + reconexión/backoff + heartbeat app
  WebSocket? socket;
  Timer? hb;
  Timer? restPoll;
  Future<void> closeSocket() async {
    hb?.cancel(); hb = null;
    try { await socket?.close(WebSocketStatus.normalClosure, 'dispose'); } catch (_) {}
    socket = null;
  }

  // Poll REST mientras WS está caído
  void startRestPoll() {
    restPoll?.cancel();
    restPoll = Timer.periodic(const Duration(seconds: 3), (_) => syncByRest());
  }
  void stopRestPoll() { restPoll?.cancel(); restPoll = null; }

  Future<void> connectLoop() async {
    int attempt = 0;

    while (!disposed) {
      try {
        if (kDebugMode) print('🔌 WS → $wsUrl');
        socket = await WebSocket.connect(
          wsUrl,
          compression: CompressionOptions.compressionDefault,
        );
        stopRestPoll(); // WS arriba → detén fallback
        attempt = 0;

        // Handshake JSON (filtros hacia el backend)
        final handshake = <String, dynamic>{
          if (types.isNotEmpty) 'types': types,
          if (families.isNotEmpty) 'families': families,
          'top': topPref,
        };
        socket!.add(jsonEncode(handshake));

        // Heartbeat de app (además del ping interval TCP)
        socket!.pingInterval = const Duration(seconds: 10);
        hb?.cancel();
        hb = Timer.periodic(const Duration(seconds: 25), (_) {
          try { socket?.add('pong'); } catch (_) {}
        });

        // Sincroniza por REST al conectar por si te perdiste algo
        unawaited(syncByRest());

        socket!.listen((dynamic data) {
          if (disposed) return;
          if (data is! String) return;

          // Ignora pings del server
          if (data == '🫀' || data.toLowerCase() == 'ping') return;

          // Esperamos un JSON array con tickets
          if (data.isEmpty || data[0] != '[') {
            if (kDebugMode) print('⚠️ payload no-JSON: $data');
            return;
          }

          try {
            final arr = (jsonDecode(data) as List);
            for (final e in arr) {
              if (e is! Map) continue;
              final m = Map<String, dynamic>.from(e);

              final id = int.tryParse('${m['id'] ?? 0}') ?? 0;
              if (id == 0) continue;

              byId[id] = Ticket(
                id: id,
                name: (m['name'] ?? m['nombre'] ?? '').toString(),
                station: (m['station'] ?? m['modulo'] ?? '').toString(),
                isManual: (m['isManual'] == true || m['EsManual'] == 1),
                tipoEspera: (m['tipoEspera'] ?? '').toString(),
              );
            }
            emit();
          } catch (e) {
            if (kDebugMode) print('❌ parse: $e');
          }
        }, onDone: () async {
          if (disposed) return;
          if (kDebugMode) print('🔌 WS cerrado (${socket?.closeCode})');
          await closeSocket();
          startRestPoll();
        }, onError: (err, st) async {
          if (disposed) return;
          if (kDebugMode) print('❌ WS error: $err');
          await closeSocket();
          startRestPoll();
        });

        // Mientras esté abierto, solo espera
        while (!disposed && socket?.readyState == WebSocket.open) {
          await Future.delayed(const Duration(seconds: 1));
        }
      } catch (e) {
        if (kDebugMode) print('❌ No se pudo abrir WS: $e');
        startRestPoll();
      } finally {
        await closeSocket();
      }

      // Backoff exponencial con techo
      attempt = (attempt + 1).clamp(1, 7);
      final delayMs = math.min(30000, 400 * (1 << (attempt - 1)));
      await Future.delayed(Duration(milliseconds: delayMs));
    }
  }

  // 6) Arranca el bucle y expone el stream
  unawaited(connectLoop());

  // Limpieza al cerrar el provider
  ref.onDispose(() async {
    stopRestPoll();
    await closeSocket();
  });

  yield* controller.stream;
});
