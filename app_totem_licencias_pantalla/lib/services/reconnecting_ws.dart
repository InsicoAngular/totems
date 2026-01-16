// lib/services/reconnecting_ws.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ReconnectingWs {
  final Uri uri;
  WebSocket? _ws;
  bool _closing = false;

  ReconnectingWs(this.uri);

  Future<void> connect() async {
    while (!_closing) {
      try {
        final ws = await WebSocket.connect(uri.toString());
        ws.pingInterval = const Duration(seconds: 30); // mantiene vivo NAT/ARR
        _ws = ws;

        ws.listen(
          (data) => onMessage?.call(data),
          onDone: _onDone,
          onError: (e, st) => _onDone(),
          cancelOnError: true,
        );
        return; // conectado
      } catch (_) {
        await Future.delayed(const Duration(seconds: 5));
      }
    }
  }

  void _onDone() {
    if (_closing) return;
    Future.delayed(const Duration(seconds: 2), connect); // reconecta
  }

  void sendJson(Map<String, dynamic> m) {
    if (_ws?.readyState == WebSocket.open) {
      _ws!.add(jsonEncode(m));
    }
  }

  void Function(dynamic data)? onMessage;

  Future<void> close() async {
    _closing = true;
    await _ws?.close();
  }
}
