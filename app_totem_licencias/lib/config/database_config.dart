// lib/config/database_config.dart
import 'dart:convert';

class DatabaseConfig {
  // ——— Parámetros de conexión SQL ———
  static const ip = String.fromEnvironment('DB_IP');
  static const port = String.fromEnvironment('DB_PORT');
  static const dbName = String.fromEnvironment('DB_NAME');
  static const user = String.fromEnvironment('DB_USER');
  static const pass = String.fromEnvironment('DB_PASS');

  // ——— Etiquetas por tipo (para UI si lo usas al revés) ———
  static const Map<String, String> labelsByTipo = {
    'P': 'Boton Primera Licencia',
    'R': 'Boton Renovacion Licencia',
    'D': 'Boton Duplicado',
    'C': 'Boton Cambio Domicilio',
    'T': 'Boton Examenes Practicos',
  };
  static String labelByTipo(String tipo) =>
      labelsByTipo[tipo.toUpperCase()] ?? tipo;

  // ——— Endpoints REST ———
  static const endpoint = String.fromEnvironment('DB_ENDPOINT'); // online
  static const apiBase = String.fromEnvironment('apiBase'); // manual

  // ➕ Endpoint práctico crear + Comuna (para el POST que pediste)
  static const practicoCrearUrl =
      String.fromEnvironment('PRACTICO_CREAR_URL', defaultValue: '');
  static const comuna =
      String.fromEnvironment('COMUNA', defaultValue: 'PUENTE ALTO');

  // ——— Flags ———
  static const bool practico = bool.fromEnvironment(
    'DB_PRACTICO',
    defaultValue: false,
  );
  static const bool mockManual = bool.fromEnvironment(
    'DB_MOCK_MANUAL',
    defaultValue: false,
  );

  // ——— Totem / perfil ———
  static const totemId = int.fromEnvironment('TOTEM_ID', defaultValue: 0);

  // ——— Tipo por defecto (para no mapeados) ———
  static const defaultTipo = String.fromEnvironment(
    'DB_DEFAULT_TIPO',
    defaultValue: 'T',
  );

  // ====== Normalización ======
  static String _normalize(String s) {
    var out = s.toLowerCase().trim();
    const f = 'áéíóúñ';
    const t = 'aeioun';
    for (var i = 0; i < f.length; i++) out = out.replaceAll(f[i], t[i]);
    return out.replaceAll(RegExp(r'\s+'), ' ');
  }

  // ====== Aliases tolerantes ======
  // Claves normalizadas para reconocer botones “Práctico”
  static final Set<String> _practicoKeys = {
    _normalize('Examen Practicos'),
    _normalize('Examenes Practicos'),
    _normalize('Práctico'),
    _normalize('Práctico C y R'),
    _normalize('Examenes Practicos C Y CR'),
  };

  static bool isPracticoLabel(String label) =>
      _practicoKeys.contains(_normalize(label));

  // Nombres EXACTOS como están en BD para buscar en ALCBotonesTotem.tramite
  static List<String> tramitesByLabel(String label) {
    final k = _normalize(label);
    if (k == _normalize('Examen Practicos') ||
        k == _normalize('Examenes Practicos')) {
      return ['Examenes Practicos', 'Examen Practicos'];
    }
    if (k == _normalize('Examenes Practicos C Y CR') ||
        k == _normalize('Práctico C y R')) {
      return ['Examenes Practicos C y CR', 'Practico C y R', 'Práctico C y R'];
    }
    if (k == _normalize('Primera Licencia')) return ['Primera Licencia'];
    if (k == _normalize('Renovacion Licencia') ||
        k == _normalize('Renovación Licencia')) {
      return ['Renovacion Licencia', 'Renovación Licencia'];
    }
    if (k == _normalize('Cambio Domicilio')) return ['Cambio Domicilio'];
    if (k == _normalize('Duplicado')) return ['Duplicado'];
    return [label]; // fallback
  }

  // ====== TRAMITE_MAP (desde --dart-define) ======
  static final String _tramiteMapRaw = const String.fromEnvironment(
    'TRAMITE_MAP',
    defaultValue: '{}',
  );

  // Mapa normalizado: "primera licencia" -> "P"
  static final Map<String, String> tramiteMap = (() {
    final raw = jsonDecode(_tramiteMapRaw) as Map<String, dynamic>;
    final out = <String, String>{};
    raw.forEach((k, v) => out[_normalize(k.toString())] = (v ?? '').toString());

    // Inyecta aliases para que no dependa del texto exacto que venga en el JSON:
    // “Examen(es) Practico(s)” y “C y CR)”
    final tipoPractico =
        out[_normalize('Examenes Practicos')] ??
            out[_normalize('Examen Practicos')] ??
            'T'; // ajusta a 'C' si en tu ALC el práctico debe ir como C
    out.putIfAbsent(_normalize('Examenes Practicos'), () => tipoPractico);
    out.putIfAbsent(_normalize('Examen Practicos'), () => tipoPractico);
    out.putIfAbsent(_normalize('Práctico'), () => tipoPractico);

    final tipoPracticoCR =
        out[_normalize('Examenes Practicos C Y CR')] ?? tipoPractico;
    out.putIfAbsent(_normalize('Examenes Practicos C Y CR'), () => tipoPracticoCR);
    out.putIfAbsent(_normalize('Práctico C y R'), () => tipoPracticoCR);

    return out;
  })();

  // Etiquetas “bonitas” como llegaron en el JSON (por si las necesitas en UI)
  static final List<String> tramiteLabels = (() {
    final dec = (jsonDecode(_tramiteMapRaw) as Map<String, dynamic>);
    return dec.keys.map((k) => k.toString()).toList();
  })();

  // Obtiene el tipo desde una etiqueta cualquiera (botón/clase2), tolerante
  static String tipoByLabel(String label) {
    final k = _normalize(label);
    final hit = tramiteMap[k];
    if (hit != null && hit.isNotEmpty) return hit;

    // Heurística: si es “práctico”, usa el tipo de práctico (o defaultTipo)
    if (isPracticoLabel(label)) {
      return tramiteMap[_normalize('Examenes Practicos')] ?? defaultTipo;
    }

    return defaultTipo;
  }
}
