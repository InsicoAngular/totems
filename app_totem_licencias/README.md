# app_totem_licencias

Resumen
-------

Proyecto Flutter para un totem de licencias. Esta app está preparada para
funcionar en Android, iOS, Windows y otras plataformas soportadas por Flutter.
El README explica cómo preparar el entorno, construir artefactos y publicar
en producción.

Requisitos
----------
- Flutter (usa la versión estable más reciente compatible).
- Android SDK + Java JDK (para builds Android).
- Xcode en macOS (para builds iOS).
- Visual Studio en Windows (para builds Windows).

Preparación rápida
------------------
1. Clona el repo:

	 git clone <repo>
	 cd app_totem_licencias

2. Instala dependencias:

	 flutter pub get

3. Archivos de configuración importantes:
- [pubspec.yaml](pubspec.yaml) — dependencias, assets y versión (`version:`).
- [lib/main.dart](lib/main.dart) — punto de entrada de la app.
- [lib/config/database_config.dart](lib/config/database_config.dart) — configuración DB.
- [assets/](assets/) — recursos embebidos.
- [android/](android/) y [ios/](ios/) — configuraciones específicas de plataforma.

Notas sobre `local.properties` y firma:
- `local.properties` debe apuntar al SDK de Android en máquinas de build.
- Para publicar en Google Play configura el keystore en `android/app` y añade
	las propiedades de firma en `android/gradle.properties` o la configuración de
	signing en `android/app/build.gradle.kts`.

Estructura relevante
---------------------
- [lib/](lib/) — código Dart de la app.
- [android/](android/) — proyecto Android y scripts Gradle.
- [ios/](ios/) — proyecto Xcode para iOS.
- [windows/], [linux/], [macos/] — runners para escritorio.
- [assets/] — imágenes y fuentes.

Cómo ejecutar localmente
------------------------
- Ejecutar en dispositivo/emulador:

	flutter run

- Ejecutar en modo release (local testing):

	flutter run --release

- Ejecutar tests:

	flutter test

Publicación — Android (resumen)
-------------------------------
1. Asegúrate de aumentar la versión en [pubspec.yaml](pubspec.yaml) (`version:`).
2. Configura el keystore y las propiedades de firma.
3. Genera el AAB (recomendado) o APK:

	 flutter build appbundle --release
	 # o
	 flutter build apk --release

4. Sube el AAB/APK a Google Play Console y sigue el flujo de distribución.

Publicación — iOS (resumen)
---------------------------
1. Debes usar macOS con Xcode instalado.
2. Ajusta el `Bundle Identifier`, perfiles de aprovisionamiento y certificados
	 en Xcode (`ios/Runner.xcodeproj` / `ios/Runner.xcworkspace`).
3. Ejecuta:

	 flutter build ipa --release

	 o usa Xcode para Archive → Upload to App Store.

Publicación — Windows (resumen)
-------------------------------
1. En Windows con Visual Studio instalado:

	 flutter build windows --release

2. El ejecutable y recursos quedan en `build\\windows\\runner\\Release`.
3. Empaqueta con el instalador/NSIS/PowerShell según tus necesidades.

Checklist mínimo antes de release
---------------------------------
- Incrementar `version` en `pubspec.yaml`.
- Ejecutar `flutter test` y `flutter analyze`.
- Verificar assets y localizaciones.
- Probar la conexión y base de datos: verifica `lib/config/database_config.dart`.
- Probar impresión y hardware si aplica (revisar `printing/` y `printing/raw_escpos.dart`).
- Actualizar notas de release / changelog.

Consejos y advertencias
-----------------------
- iOS: la firma y perfiles suelen ser la parte más problemática; usa Xcode para
	resolver provisioning issues.
- Android: `local.properties` debe reflejar la ruta al SDK en el CI/build agent.
- Para builds automatizados (CI), almacena secretos (keystore, claves) en el
	sistema de CI y no en el repo.

Contacto y responsabilidad
--------------------------
Si algo falla durante la publicación o el empaquetado, revisa los logs de
build y comparte mensajes de error completos. Para tareas específicas, ver
estos archivos ayuda al diagnóstico: [pubspec.yaml](pubspec.yaml),
[lib/main.dart](lib/main.dart), [android/app/build.gradle.kts](android/app/build.gradle.kts).

