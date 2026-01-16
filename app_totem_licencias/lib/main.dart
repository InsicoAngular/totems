// lib/main.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'config/database_config.dart';
import 'services/database_service.dart';

// Kiosk / Rutas
import 'kiosk_shell.dart';
import 'screens/start_screen.dart';
import 'screens/numeric_pad_screen.dart';
import 'screens/result_screen.dart';
import 'screens/error_screen.dart';
import 'screens/tramites_screen.dart';
import 'screens/manual_tramite_screen.dart';
import 'screens/practico_operator_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Carga config remota (textos/colores/assets) si hay TOTEM_ID
  await _loadRemoteConfigIfAny();

  // 2) Flags por línea de comando
  //    Aceptamos ambos para tu build: --dart-define=DISABLE_KIOSK=true o NO_KIOSK=true
  const disableKioskFlag = bool.fromEnvironment(
    'DISABLE_KIOSK',
    defaultValue: false,
  );
  const noKioskFlag = bool.fromEnvironment('NO_KIOSK', defaultValue: false);
  final disableKiosk = disableKioskFlag || noKioskFlag;

  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  final kioskOn = isDesktop && !disableKiosk; // kiosk habilitado?
  final hardKiosk = kioskOn && kReleaseMode; // “duro” solo en release
  final operatorMode =
      DatabaseConfig.practico && !kioskOn; // PC del operador práctico sin kiosk

  // 3) Configura ventana:
  //    - Si kiosk ON → inicializa kiosk shell (fullscreen/bloqueos)
  //    - Si kiosk OFF → ventana normal y centrada, con barra de título
  if (isDesktop) {
    if (kioskOn) {
      try {
        await KioskShell.initWindowKiosk(hard: hardKiosk);
      } catch (e) {
        debugPrint('⚠️ No se pudo iniciar modo kiosk: $e');
      }
    } else {
      // Ventana normal (operador)
      await windowManager.ensureInitialized();
      const opts = WindowOptions(
        size: Size(1100, 780),
        center: true,
        titleBarStyle: TitleBarStyle.normal,
        title: 'Operador · Examen Práctico',
      );
      await windowManager.waitUntilReadyToShow(opts, () async {
        await windowManager.setResizable(true);
        await windowManager.setFullScreen(false);
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setSkipTaskbar(false);
        await windowManager.setPreventClose(false);
        await windowManager.show();
        await windowManager.focus();
      });
    }
  }

  // 4) Mantener pantalla despierta
  try {
    await WakelockPlus.enable();
  } catch (_) {}

  runApp(
    ProviderScope(
      child: MyApp(
        kioskEnabled: kioskOn,
        hardKiosk: hardKiosk,
        operatorMode: operatorMode,
      ),
    ),
  );
}

/// Lee TO_TotemConfig.ConfigJson y persiste textos/colores/assetsDir
Future<void> _loadRemoteConfigIfAny() async {
  final totemId = DatabaseConfig.totemId;
  if (totemId == 0) return;

  String? raw;
  try {
    raw = await DatabaseService.instance.fetchConfigJson();
  } catch (e) {
    debugPrint('⚠️  Error al leer ConfigJson remoto: $e');
    return;
  }
  if (raw == null) return;

  Map<String, dynamic> cfg;
  try {
    cfg = jsonDecode(raw) as Map<String, dynamic>;
  } catch (e) {
    debugPrint('⚠️  ConfigJson corrupto → ignorado ($e)');
    return;
  }

  debugPrint('[BOOT] DB_PRACTICO = ${DatabaseConfig.practico}');

  final prefs = await SharedPreferences.getInstance();
  await prefs
    ..setString('welcomeText', cfg['welcomeText'] ?? '')
    ..setString('hashtag', cfg['hashtag'] ?? '')
    ..setString('marqueeText', cfg['marqueeText'] ?? '')
    ..setInt('buttonBg', cfg['buttonBg'] ?? Colors.deepPurple.value)
    ..setInt('buttonText', cfg['buttonText'] ?? Colors.white.value)
    ..setString('assetsDir', cfg['assetsDir'] ?? r'C:\Insico\assets\');
}

class MyApp extends StatelessWidget {
  final bool kioskEnabled;
  final bool hardKiosk;
  final bool operatorMode; // práctico + sin kiosk

  const MyApp({
    super.key,
    required this.kioskEnabled,
    required this.hardKiosk,
    required this.operatorMode,
  });

  @override
  Widget build(BuildContext context) {
    // Si es PC del operador (práctico sin kiosk), parte directo en la pantalla del operador.
    final String initial = operatorMode ? '/practico-ops' : '/';

    return MaterialApp(
      title: 'App Tótem',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),

      // Captura Ctrl+Alt+Q / bloqueos sólo si kiosk está habilitado
      builder:
          (context, child) =>
              kioskEnabled
                  ? KioskShell(
                    hard: hardKiosk,
                    child: child ?? const SizedBox(),
                  )
                  : (child ?? const SizedBox()),

      initialRoute: initial,
      routes: {
        '/': (_) => const StartScreen(),
        '/pad': (_) => const NumericPadScreen(),
        '/result': (_) => const ResultScreen(),
        '/error': (_) => const ErrorScreen(),
        '/tramites': (_) => const TramitesScreen(),
        '/manual': (_) => const ManualTramiteScreen(),
        '/practico-ops': (_) => const PracticoOperatorScreen(),
      },
    );
  }
}
