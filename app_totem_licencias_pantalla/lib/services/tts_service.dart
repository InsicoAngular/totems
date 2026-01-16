// lib/services/tts_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsService {
  final _player = AudioPlayer();

  // ===== Config =====
  String _backend = 'azure';                 // 'azure' | 'google'
  double _rate   = 0.5;                      // 0..1
  double _pitch  = 1.0;                      // 0.5..2
  double _volume = 1.0;                      // 0..1
  bool _ready = false;

  // ===== Azure =====
  String _azKey    = '';
  String _azRegion = 'eastus2';
  String _azVoice  = 'es-ES-AlvaroNeural';
  String _azLocale = 'es-ES';
  String? _azToken;
  DateTime _azTokExp = DateTime.fromMillisecondsSinceEpoch(0);

  // ===== Google (fallback opcional) =====
  String _gKey   = '';
  String _gVoice = 'es-ES-Neural2-C';
  String _gLang  = 'es-ES';

  // ===== Title case + fixes =====
  static const _lowerWords = {'de','del','la','las','los','y','o','u','da','do','das','dos','e'};
  static final Map<RegExp,String> _pronFix = {
    RegExp(r'\bponiatowsky\b', caseSensitive: false): 'Poniatovski',
  };

Future<void> init() async {
  final prefs = await SharedPreferences.getInstance();
  _backend = prefs.getString('ttsBackend') ?? _backend;

  // Azure
  _azKey    = prefs.getString('ttsAzureKey')    ?? _azKey;
  _azRegion = prefs.getString('ttsAzureRegion') ?? _azRegion;
  _azVoice  = prefs.getString('ttsAzureVoice')  ?? _azVoice;
  _azLocale = prefs.getString('ttsLocale')      ?? _azLocale;

  // Si hay key de Azure, fuerza Azure + Lorenzo por si quedó Google viejo
  if (_azKey.isNotEmpty) {
    _backend  = 'azure';
    _azVoice  = (_azVoice.isEmpty) ? 'es-CL-LorenzoNeural' : _azVoice;
    _azLocale = (_azLocale.isEmpty) ? 'es-CL' : _azLocale;
  }

  // comunes
  _rate   = prefs.getDouble('ttsRate')   ?? _rate;
  _pitch  = prefs.getDouble('ttsPitch')  ?? _pitch;
  _volume = prefs.getDouble('ttsVolume') ?? _volume;

  debugPrint('[TTS] backend=$_backend  azure=$_azRegion/$_azVoice');
  _ready = true;
}

  Future<void> dispose() async { try { await _player.dispose(); } catch (_) {} }
  Future<void> stop() async    { try { await _player.stop();    } catch (_) {} }

  // =================== API pública ===================
  Future<void> speak(String textOrSsml) async {
    if (!_ready) return;
    try {
      final isSsml = textOrSsml.trimLeft().startsWith('<');
      String path;
      if (_backend == 'azure') {
        if (_azKey.isEmpty) { debugPrint('[TTS] Falta ttsAzureKey'); return; }
        path = await _synthesizeAzure(textOrSsml, isSsml: isSsml);
      } else {
        if (_gKey.isEmpty) { debugPrint('[TTS] Falta ttsGoogleKey'); return; }
        path = await _synthesizeGoogle(textOrSsml, isSsml: isSsml);
      }
      await _play(path);
    } catch (e, st) {
      debugPrint('[TTS] Error al sintetizar/reproducir: $e\n$st');
    }
  }

  Future<void> speakCall({required String nombre, required String modulo}) async {
    final nombreOk = (nombre.trim().isEmpty) ? 'Siguiente usuario' : normalizePersonName(nombre);
    final stationSsml = stationToSsml(modulo.isEmpty ? 'Módulo 1' : modulo);
    final ssml = buildCallSsml(nombre: nombreOk, stationSsml: stationSsml);
    await speak(ssml);
  }

  // =================== helpers de texto ===================
  String normalizePersonName(String raw) {
    var s = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final parts = s.split(' ');
    final buf = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      var w = parts[i];
      if (_lowerWords.contains(w) && i != 0) buf.write(w);
      else if (w.isNotEmpty) buf.write(w[0].toUpperCase() + w.substring(1));
      if (i < parts.length - 1) buf.write(' ');
    }
    var out = buf.toString();
    _pronFix.forEach((re, rep) => out = out.replaceAll(re, rep));
    return out;
  }

  String stationToSsml(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    final m = RegExp(r'^(?:(SOLICITUD|M[OÓ]DULO|VENTANILLA)\s+)?(\d+)$', caseSensitive: false).firstMatch(s);
    if (m != null) {
      final label = m.group(1)?.toLowerCase() ?? 'módulo';
      final num = m.group(2)!;
      final nice = (label.startsWith('solicitud')) ? 'Solicitud'
                : (label.startsWith('ventanilla')) ? 'Ventanilla' : 'Módulo';
      return '$nice <say-as interpret-as="cardinal">$num</say-as>';
    }
    return s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  String buildCallSsml({required String nombre, required String stationSsml}) => '''
<speak>
  <prosody rate="0.97">
    $nombre. <break time="250ms"/> $stationSsml.
  </prosody>
</speak>
''';

  // =================== IO / cache / player ===================
  Future<String> _cacheDir() async {
    final dir = await getTemporaryDirectory();
    final d = Directory('${dir.path}${Platform.pathSeparator}tts_cache');
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }

  Future<String> _cachedPath({required String backend, required String voice, required String key}) async {
    final h = md5.convert(utf8.encode('$backend|$voice|$_rate|$_pitch|$_volume|$key')).toString();
    final base = await _cacheDir();
    return '$base${Platform.pathSeparator}$backend-$voice-$h.mp3';
  }

  Future<void> _play(String filePath) async {
    await _player.stop();
    await _player.setVolume(_volume.clamp(0.0, 1.0));
    await _player.play(DeviceFileSource(filePath));
  }

  // =================== Azure ===================
  Future<String> _synthesizeAzure(String input, {bool isSsml = false}) async {
    final keyForCache = '${isSsml ? "ssml" : "txt"}|$input';
    final filePath = await _cachedPath(backend: 'azure', voice: _azVoice, key: keyForCache);
    if (await File(filePath).exists()) return filePath;

    final token = await _getAzureToken(); // ~10 min

    String _signedPct(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(0)}%';
    final ratePct  = ((_rate - 0.5) * 2.0 * 50.0).clamp(-50.0, 50.0);
    final pitchPct = ((_pitch - 1.0) * 100.0 / 2.0).clamp(-50.0, 50.0);

    final inner = isSsml
        ? input.replaceAll(RegExp(r'</?speak[^>]*>', caseSensitive: false), '')
        : _xmlEscape(input);

    final ssml = '''
<speak version="1.0"
       xmlns="http://www.w3.org/2001/10/synthesis"
       xmlns:mstts="https://www.w3.org/2001/mstts"
       xml:lang="$_azLocale">
  <voice name="$_azVoice">
    <prosody rate="${_signedPct(ratePct)}" pitch="${_signedPct(pitchPct)}">
      $inner
    </prosody>
  </voice>
</speak>
''';

    final url = Uri.parse('https://$_azRegion.tts.speech.microsoft.com/cognitiveservices/v1');
    final res = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/ssml+xml',
        'X-Microsoft-OutputFormat': 'audio-24khz-96kbitrate-mono-mp3',
        'User-Agent': 'totem-tts/1.0',
      },
      body: utf8.encode(ssml),
    );
    if (res.statusCode != 200) {
      throw 'Azure TTS ${res.statusCode}: ${res.body}';
    }

    await File(filePath).writeAsBytes(res.bodyBytes, flush: true);
    return filePath;
  }

  Future<String> _getAzureToken() async {
    final now = DateTime.now();
    if (_azToken != null && now.isBefore(_azTokExp)) return _azToken!;
    final url = Uri.parse('https://$_azRegion.api.cognitive.microsoft.com/sts/v1.0/issueToken');
    final res = await http.post(url, headers: {'Ocp-Apim-Subscription-Key': _azKey});
    if (res.statusCode != 200) {
      throw 'Azure token ${res.statusCode}: ${res.body}';
    }
    _azToken = res.body;
    _azTokExp = now.add(const Duration(minutes: 9));
    return _azToken!;
  }

  // =================== Google (opcional) ===================
  Future<String> _synthesizeGoogle(String input, {bool isSsml = false}) async {
    final keyForCache = '${isSsml ? "ssml" : "txt"}|$input';
    final filePath = await _cachedPath(backend: 'google', voice: _gVoice, key: keyForCache);
    if (await File(filePath).exists()) return filePath;

    final speakingRate = (_rate <= 0 ? 0.25 : (0.25 + _rate * 1.5));
    final pitchSt      = ((_pitch - 1.0) * 10.0).clamp(-20.0, 20.0);
    final gainDb       = ((_volume - 1.0) * 10.0).clamp(-96.0, 16.0);

    final url  = Uri.parse('https://texttospeech.googleapis.com/v1/text:synthesize?key=$_gKey');
    final body = {
      'input': isSsml ? {'ssml': input} : {'text': input},
      'voice': {'languageCode': _gLang, 'name': _gVoice},
      'audioConfig': {
        'audioEncoding': 'MP3',
        'speakingRate': speakingRate,
        'pitch': pitchSt,
        'volumeGainDb': gainDb,
      }
    };

    final res = await http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (res.statusCode != 200) {
      throw 'Google TTS ${res.statusCode}: ${res.body}';
    }

    final jsonMap  = jsonDecode(res.body) as Map<String, dynamic>;
    final audioB64 = jsonMap['audioContent'] as String? ?? '';
    if (audioB64.isEmpty) throw 'Respuesta sin audioContent';

    final bytes = base64Decode(audioB64);
    await File(filePath).writeAsBytes(bytes, flush: true);
    return filePath;
  }

  // =================== Diagnóstico ===================
  Future<String> _generateWavBeep({
    double seconds = 0.5, int sampleRate = 44100, double freq = 440.0,
  }) async {
    final samples = (seconds * sampleRate).floor();
    final bytesPerSample = 2;
    final dataLen = samples * bytesPerSample;
    final byteData = BytesBuilder();

    void _w16(int v) => byteData.add([v & 0xFF, (v >> 8) & 0xFF]);
    void _w32(int v) => byteData.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

    byteData.add([0x52,0x49,0x46,0x46]); _w32(36 + dataLen);
    byteData.add([0x57,0x41,0x56,0x45]);
    byteData.add([0x66,0x6D,0x74,0x20]); _w32(16);
    _w16(1); _w16(1); _w32(sampleRate); _w32(sampleRate*2); _w16(2); _w16(16);
    byteData.add([0x64,0x61,0x74,0x61]); _w32(dataLen);

    for (int i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final s = math.sin(2*math.pi*freq*t);
      final amp = (s * 0.3 * 32767).round();
      _w16(amp & 0xFFFF);
    }

    final path = '${await _cacheDir()}${Platform.pathSeparator}beep.wav';
    await File(path).writeAsBytes(byteData.toBytes(), flush: true);
    return path;
  }

  Future<void> debugSelfTestUI(BuildContext ctx) async {
    final log = StringBuffer();
    log.writeln('=== DIAGNÓSTICO TTS ===');
    log.writeln('Backend: $_backend  Rate=$_rate  Pitch=$_pitch  Vol=$_volume');

    try {
      final beep = await _generateWavBeep();
      log.writeln('Beep WAV: $beep');
      await _player.setVolume(_volume.clamp(0.0, 1.0));
      await _player.stop();
      await _player.play(DeviceFileSource(beep));
    } catch (e) { log.writeln('Beep ERROR: $e'); }

    try {
      final f = (_backend=='azure')
          ? await _synthesizeAzure('Prueba de voz de Azure. Hola desde el tótem.')
          : await _synthesizeGoogle('Prueba de voz de Google. Hola desde el tótem.');
      final size = await File(f).length();
      log.writeln('MP3 TTS: $f  (${size} bytes)');
      await _player.stop();
      await _player.play(DeviceFileSource(f));
      try { await Process.run('explorer', [f]); } catch (_) {}
    } catch (e) { log.writeln('TTS ERROR: $e'); }

    if (ctx.mounted) {
      await showDialog(
        context: ctx,
        builder: (_) => AlertDialog(
          title: const Text('Diagnóstico TTS'),
          content: SingleChildScrollView(child: Text(log.toString())),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }

  String _xmlEscape(String s) => s
      .replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')
      .replaceAll('"','&quot;').replaceAll("'",'&apos;');
}
