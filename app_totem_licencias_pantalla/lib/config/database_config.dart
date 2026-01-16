/// Configuración inyectada vía --dart-define.
/// WS_URL y TIPO_ESPERA sirven para bootstrap del tótem.
class DatabaseConfig {
  static const ip      = String.fromEnvironment('DB_IP',     defaultValue: '');
  static const port    = String.fromEnvironment('DB_PORT',   defaultValue: '1433');
  static const dbName  = String.fromEnvironment('DB_NAME',   defaultValue: '');
  static const user    = String.fromEnvironment('DB_USER',   defaultValue: '');
  static const pass    = String.fromEnvironment('DB_PASS',   defaultValue: '');
  static const totemId = int.fromEnvironment('TOTEM_ID',     defaultValue: 0);

  /// URL del WebSocket
  static const wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://localhost:5161/ws/tickets',
  );

  /// Tipo de espera por default para este tótem (puede ser CSV o "*")
  static const tipoEspera = String.fromEnvironment(
    'TIPO_ESPERA',
    defaultValue: '*',
  );

  static void validate() {
    final missing = <String>[
      if (ip.isEmpty)     'DB_IP',
      if (dbName.isEmpty) 'DB_NAME',
      if (user.isEmpty)   'DB_USER',
      if (pass.isEmpty)   'DB_PASS',
    ];
    if (missing.isNotEmpty) {
      throw StateError('Faltan --dart-define: ${missing.join(", ")}');
    }
  }
}
