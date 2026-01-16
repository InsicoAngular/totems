// lib/kiosk_shell.dart
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Intent personalizado para la salida secreta
class _CloseAppIntent extends Intent {
  const _CloseAppIntent();
}

/// Widget que envuelve TODA la app para:
/// - Atajo oculto Ctrl+Alt+Q (salida)
/// - Focus global para captar teclas
class KioskShell extends StatelessWidget {
  final Widget child;
  final bool hard; // true => previene cerrar (kiosk duro)
  final bool enableSecretExit;

  const KioskShell({
    super.key,
    required this.child,
    this.hard = true,
    this.enableSecretExit = true,
  });

  /// Inicializa ventana en modo kiosko (desktop).
  static Future<void> initWindowKiosk({required bool hard}) async {
    await windowManager.ensureInitialized();

    const options = WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      if (hard) await windowManager.setPreventClose(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setFullScreen(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Mapeo del atajo: Ctrl + Alt + Q
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.keyQ, control: true, alt: true):
          const _CloseAppIntent(),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CloseAppIntent: CallbackAction<_CloseAppIntent>(
            onInvoke: (intent) {
              if (!enableSecretExit) return null;

              // Salida segura: deshabilita preventClose y cierra.
              unawaited(() async {
                try {
                  if (hard) {
                    await windowManager.setPreventClose(false);
                  }
                } catch (_) {
                  /* ignore */
                }
                try {
                  if (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS) {
                    await windowManager.close();
                  } else {
                    SystemNavigator.pop();
                  }
                } catch (_) {
                  exit(0);
                }
              }());

              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
