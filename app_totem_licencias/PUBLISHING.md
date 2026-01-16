Guía de publicación — app_totem_licencias
=====================================

Esta guía explica paso a paso cómo publicar la app `app_totem_licencias` en
Android (Google Play), iOS (App Store) y Windows (instalador). Incluye
recomendaciones para CI, gestión de claves y checklist previo al release.

Índice
------
- Requisitos
- Preparación común
- Android (Google Play)
- iOS (App Store)
- Windows (desktop)
- CI / Automatización (ejemplos)
- Checklist de release
- Troubleshooting rápido

Requisitos
----------
- Tener instalado Flutter (stable) y configuración de plataformas necesarias.
- Android: Android SDK, JDK (OpenJDK 11+), `local.properties` apuntando al SDK.
- iOS: Xcode (en macOS), cuenta Apple Developer activa.
- Windows: Visual Studio con workloads para C++/desktop.

Preparación común
------------------
1. Actualiza la versión en `pubspec.yaml`. Ejemplo: `version: 1.2.3+45` donde
   `1.2.3` es la versión legible y `45` es el número de build.
2. Ejecuta dependencias y tests:

   flutter pub get
   flutter analyze
   flutter test

3. Verifica assets y localizaciones.

Android (Google Play)
---------------------
1. Firma / keystore
   - Si no tienes keystore, créalo (ejemplo):

     keytool -genkey -v -keystore release.jks -alias app_key -keyalg RSA -keysize 2048 -validity 10000

   - Coloca `release.jks` fuera del repo (p.ej. en el agente CI o en carpeta segura).
   - Añade las propiedades en `android/gradle.properties` o en variables de CI:

     SIGNING_STORE_FILE=path/to/release.jks
     SIGNING_STORE_PASSWORD=xxxxx
     SIGNING_KEY_ALIAS=app_key
     SIGNING_KEY_PASSWORD=xxxxx

   - Configura el signing config en `android/app/build.gradle.kts` (ya puede estar
     preconfigurado en el repo; verifica `android/app`).

2. Incrementa `version` en `pubspec.yaml` antes del release.
3. Genera AAB (recomendado) o APK:

   flutter build appbundle --release
   # o
   flutter build apk --release

4. Sube a Google Play Console (Internal / Closed / Production) y completa
   release notes, pruebas, y dispositivos target.

iOS (App Store)
----------------
1. Requisitos previos
   - macOS con Xcode instalado.
   - Cuenta Apple Developer (mínimo Developer Program).

2. Identificadores y provisioning
   - Ajusta el `Bundle Identifier` en Xcode (`ios/Runner` target).
   - Crea App ID, certificados y perfiles de aprovisionamiento en Apple
     Developer portal o usa Xcode Automatic Signing.

3. Firma y build
   - Actualiza la versión en `pubspec.yaml`.
   - Para generar IPA:

     flutter build ipa --release

   - Alternativa: abrir `ios/Runner.xcworkspace` en Xcode → Product → Archive
     → Validate / Distribute.

4. Sube a App Store Connect y completa metadatos, capturas de pantalla y pruebas
   en TestFlight antes de enviar a revisión.

Windows (desktop)
------------------
1. En Windows con Visual Studio instalado:

   flutter build windows --release

2. El binario queda en `build\windows\runner\Release`.
3. Empaqueta en instalador (NSIS, Inno Setup, MSIX) según necesidades.

CI / Automatización (ejemplos)
------------------------------
Recomendaciones generales
- Nunca guardes keystores o secretos en el repo.
- Usa secretos del proveedor CI (GitHub Actions Secrets, GitLab CI variables,
  Azure DevOps secure files).

Ejemplo (snippet GitHub Actions) - Android AAB

```yaml
name: Build Android AAB
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: subosito/flutter-action@v2
      with:
        flutter-version: 'stable'
    - name: Install JDK
      uses: actions/setup-java@v3
      with:
        distribution: 'temurin'
        java-version: '11'
    - name: Decrypt keystore
      run: |
        echo "$KEYSTORE_BASE64" | base64 -d > release.jks
      env:
        KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
    - name: flutter pub get
      run: flutter pub get
    - name: Build AAB
      run: flutter build appbundle --release
    - name: Upload artifact
      uses: actions/upload-artifact@v4
      with:
        name: appbundle
        path: build/app/outputs/bundle/release/*.aab
```


Notas públicas (contenido original de `public.json`)
-----------------------------------------------

Ejemplo de comandos y flags (sintaxis de shell):

```sh
# Puente Alto

flutter build windows --release \
  --dart-define=DB_IP=10.1.17.25 \
  --dart-define=DB_PORT=1433 \
  --dart-define=DB_NAME=Puentealto_web_muni \
  --dart-define=DB_USER=insico \
  --dart-define=DB_PASS=<REDACTED> \
  --dart-define=DB_DEFAULT_TIPO=P \
  --dart-define=TRAMITE_MAP='{"Primera Licencia":"P","Renovacion Licencia":"C","Duplicado":"D","Cambio Domicilio":"D"}' \
  --dart-define=TOTEM_ID=1 \
  --dart-define=DB_ENDPOINT=https://apipuente.reservandotuhora.cl \
  --dart-define=apiBase=https://api.reservandotuhora.cl \
  --dart-define=DB_PRACTICO=false \
  --dart-define=DB_MOCK_MANUAL=false \
  --dart-define=NO_KIOSK=false \
  --dart-define=PRACTICO_CREAR_URL=https://apipuente.reservandotuhora.cl/apipractico/practico-tablet/crear \
  --dart-define=COMUNA="PUENTE ALTO"

flutter run -d windows \
  --dart-define=DB_IP=200.75.12.92 \
  --dart-define=DB_PORT=1433 \
  --dart-define=DB_NAME=Puentealto_web_muni \
  --dart-define=DB_USER=insico \
  --dart-define=DB_PASS=<REDACTED> \
  --dart-define=DB_DEFAULT_TIPO=P \
  --dart-define=TRAMITE_MAP='{"Primera Licencia":"P","Renovacion Licencia":"C","Duplicado":"D","Cambio Domicilio":"D"}' \
  --dart-define=TOTEM_ID=1 \
  --dart-define=DB_ENDPOINT=https://apipuente.reservandotuhora.cl \
  --dart-define=apiBase=https://api.reservandotuhora.cl \
  --dart-define=DB_PRACTICO=true \
  --dart-define=DB_MOCK_MANUAL=false \
  --dart-define=NO_KIOSK=true \
  --dart-define=PRACTICO_CREAR_URL=https://apipuente.reservandotuhora.cl/apipractico/practico-tablet/crear \
  --dart-define=COMUNA="PUENTE ALTO"

# Notas:
# - Reemplaza valores sensibles (p.ej. DB_PASS) por secretos en tu CI.
# - `TOTEM_ID` cambia según el modo: 1=Atención, 2=Pantalla, 3=Práctico.
# - No dejes estos comandos con credenciales en el repo público.
```
