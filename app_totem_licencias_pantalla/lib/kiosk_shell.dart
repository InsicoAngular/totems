// lib/kiosk_shell.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Intent explícito para salir con atajo.
class ExitAppIntent extends Intent {
  const ExitAppIntent();
}

class KioskShell extends StatelessWidget {
  final Widget child;
  const KioskShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          // Ctrl + Alt + Q
          SingleActivator(
            LogicalKeyboardKey.keyQ,
            control: true,
            alt: true,
          ): ExitAppIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            ExitAppIntent: CallbackAction<ExitAppIntent>(
              onInvoke: (intent) {
                // Ejecutar asíncrono para no bloquear el ciclo de Actions
                () async {
                  try {
                    // Quita el candado que pusiste en release
                    await windowManager.setPreventClose(false);
                  } catch (_) {}

                  try {
                    // Cierre contundente de la ventana (salta handlers de close)
                    await windowManager.destroy();
                    return;
                  } catch (_) {}

                  try {
                    // Fallback cross-platform
                    await SystemNavigator.pop();
                    return;
                  } catch (_) {}

                  // Último recurso
                  exit(0);
                }();

                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: child,
          ),
        ),
      ),
    );
  }
}
