// lib/services/websocket_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/ticket.dart';
import '../config/database_config.dart';

class WebSocketService {
  WebSocket? _ws;
  final _controller = StreamController<List<Ticket>>.broadcast();
  Stream<List<Ticket>> get stream => _controller.stream;

  // Reintento exponencial simple
  Duration _delay = const Duration(seconds: 2);
  Timer? _retryTimer;

  Future<void> connect() async {
    await _open();
  }

  Future<void> _open() async {
    try {
      _ws = await WebSocket.connect(DatabaseConfig.wsUrl);
      _ws!.pingInterval = const Duration(seconds: 20);          // opcional
      _ws!.add(DatabaseConfig.tipoEspera);                      // handshake ①

      _delay = const Duration(seconds: 2);                      // reset back-off
      _ws!.listen(
        _onData,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic data) {
    if (data == '🫀') return;                                    // ② latido
    try {
      final list = (jsonDecode(data as String) as List)
          .map((e) => Ticket.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _controller.add(list);
    } catch (_) {/* ignore parse errors */}
  }

  void _scheduleReconnect() {
    _retryTimer?.cancel();
    _retryTimer = Timer(_delay, _open);
    _delay *= 2;                                                // back-off
    if (_delay > const Duration(minutes: 1)) {
      _delay = const Duration(minutes: 1);
    }
  }

  void dispose() {
    _retryTimer?.cancel();
    _ws?.close(WebSocketStatus.goingAway);
    _controller.close();
  }
}
