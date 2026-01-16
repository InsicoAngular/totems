Contenido movido desde `public.json`
====================================

El archivo `public.json` contenía comandos y flags para build/run. Se recomienda
no mantener secretos en archivos del repo. Aquí están las notas originales
(contraseñas reemplazadas por `<REDACTED>`):

```sh
// Puente Alto

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

// Notas adicionales:
// - TOTEM_ID: 1=Atencion, 2=Pantalla, 3=Práctico
// - Evitar subir `release.jks` y contraseñas al repo.
```

Ubicación nueva: `PUBLISHING.md` también incluye una sección con estas notas.
