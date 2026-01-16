// lib/main.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'services/database_service.dart';
import 'screens/waiting_screen.dart';
import 'kiosk_shell.dart';

/// ===================== LOG BÁSICO A ARCHIVO =====================
late final File _logFile;
void _log(Object msg, [StackTrace? st]) {
  final line = '[${DateTime.now().toIso8601String()}] $msg'
      '${st != null ? '\n$st' : ''}\n';
  try {
    _logFile.writeAsStringSync(line, mode: FileMode.append);
  } catch (_) {}
  debugPrint(line);
}

/// ===================== PREFS / CONFIG REMOTA =====================
/// Si existe config remota desde la BD, la aplica.
/// Respeta backend que venga (azure|google). Si no viene, mantiene el actual
/// o usa 'azure' por defecto.
Future<void> _forceAzureLorenzo() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('ttsBackend', 'azure');
  await prefs.setString('ttsAzureRegion', 'eastus2');
  await prefs.setString('ttsAzureVoice',  'es-CL-LorenzoNeural'); // ✅ correcta
  await prefs.setString('ttsLocale',      'es-CL');

  // ⚠️ Pega AQUI tu key real de Azure Speech:
  await prefs.setString('ttsAzureKey', 'ABLSWtTWVXlDcns5y8yn7BaS9oCct0hZDW4WX7H8OrEFCS8TPdF2JQQJ99BIACHYHv6XJ3w3AAAYACOGpP2z');

  // Para no caer a Google por accidente
  await prefs.remove('ttsGoogleKey');
}

Future<void> _loadRemotePrefsIfAny() async {
  try {
    final raw = await DatabaseService.instance.fetchConfigJson();
    if (raw == null || raw.trim().isEmpty) return;

    final cfg = json.decode(raw) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();

    // backend (azure | google)
    final remoteBackend = (cfg['ttsBackend'] as String?)?.trim();
    final currentBackend = prefs.getString('ttsBackend') ?? 'azure';
    await prefs.setString('ttsBackend', remoteBackend?.isNotEmpty == true ? remoteBackend! : currentBackend);

    // ===== Azure (si viene) =====
    Future<void> _setStr(String key, String prefKey) async {
      final v = cfg[key];
      if (v is String && v.trim().isNotEmpty) {
        await prefs.setString(prefKey, v.trim());
      }
    }

    await _setStr('ttsAzureKey',    'ttsAzureKey');
    await _setStr('ttsAzureRegion', 'ttsAzureRegion'); // p.ej: eastus2
    await _setStr('ttsAzureVoice',  'ttsAzureVoice');  // p.ej: es-ES-AlvaroNeural

    // ===== Google (si lo usas como fallback) =====
    await _setStr('ttsGoogleKey',   'ttsGoogleKey');
    await _setStr('ttsGoogleLang',  'ttsGoogleLang');   // p.ej: es-ES
    await _setStr('ttsGoogleVoice', 'ttsGoogleVoice');  // p.ej: es-ES-Neural2-C

    // ===== Parámetros comunes =====
    Future<void> _setNum(String key, String prefKey) async {
      final v = cfg[key];
      if (v is num) await prefs.setDouble(prefKey, v.toDouble());
      if (v is String && v.isNotEmpty) {
        final p = double.tryParse(v);
        if (p != null) await prefs.setDouble(prefKey, p);
      }
    }

    await _setStr('ttsLocale', 'ttsLocale'); // p.ej: es-CL
    await _setNum('ttsRate',   'ttsRate');   // 0..1 (mapeado en tu servicio)
    await _setNum('ttsPitch',  'ttsPitch');  // 0.5..2
    await _setNum('ttsVolume', 'ttsVolume'); // 0..1
  } catch (e, st) {
    _log('loadRemotePrefsIfAny failed: $e', st);
  }
}

/// Prefs por defecto si no existen.
/// Dejamos **Azure** como backend por defecto (cambia la voice si quieres).
Future<void> _seedTtsPrefsIfEmpty() async {
  final prefs = await SharedPreferences.getInstance();
  if (!prefs.containsKey('ttsBackend')) {
    await prefs
      ..setString('ttsBackend', 'azure')
      ..setString('ttsAzureKey',    'ABLSWtTWVXlDcns5y8yn7BaS9oCct0hZDW4WX7H8OrEFCS8TPdF2JQQJ99BIACHYHv6XJ3w3AAAYACOGpP2z')            // pega tu Key aquí o por config remota
      ..setString('ttsAzureRegion', 'eastus2')     // el de tu screenshot
      ..setString('ttsAzureVoice',  'es-ES-LorenzoNeural') // voz masculina natural
      ..setString('ttsLocale',      'es-CL')
      ..setDouble('ttsRate',  0.5)
      ..setDouble('ttsPitch', 1.0)
      ..setDouble('ttsVolume',1.0);
  }
}

/// ===================== WINDOW / KIOSKO =====================
Future<void> _initWindowKiosk({required bool hard}) async {
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Colors.transparent,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    if (hard) {
      await windowManager.setPreventClose(true); // solo release
      await windowManager.setSkipTaskbar(true);
      await windowManager.setAlwaysOnTop(true);
    }
    await windowManager.setFullScreen(true);
    await windowManager.show();
    await windowManager.focus();
  });

  // Mantener pantalla despierta
  await WakelockPlus.enable();
}

/// ===================== MAIN =====================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Archivo de log (Windows %TEMP%)
  _logFile = File('${Directory.systemTemp.path}${Platform.pathSeparator}totem_ui.log');

  // Prefs TTS: primero semilla local, luego (si hay) remotas
  await _seedTtsPrefsIfEmpty();
  await _loadRemotePrefsIfAny();

  // Captura global de errores para que no “mate” el proceso sin rastro
  FlutterError.onError = (details) {
    _log('FlutterError: ${details.exceptionAsString()}', details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _log('ZoneError: $error', stack);
    return true;
  };
  await _forceAzureLorenzo();     // 👈 añade esta línea

  // Flags de runtime (usar true/false; no 0/1)
  const disableKiosk = bool.fromEnvironment('DISABLE_KIOSK', defaultValue: false);
  const disableTts   = bool.fromEnvironment('DISABLE_TTS',   defaultValue: false);

  // Ventana kiosko
  try {
    if (!disableKiosk) {
      await _initWindowKiosk(hard: kReleaseMode);
    }
  } catch (e, st) {
    _log('kiosk init failed: $e', st);
  }

  runApp(ProviderScope(child: MyApp(disableTts: disableTts)));
}

class MyApp extends StatelessWidget {
  final bool disableTts;
  const MyApp({super.key, required this.disableTts});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waiting Screen',
      debugShowCheckedModeBanner: false,
      home: KioskShell(child: WaitingScreen(disableTts: disableTts)),
    );
  }
}
