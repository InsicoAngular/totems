class DatabaseConfig {
  static const ip       = String.fromEnvironment('DB_IP');
  static const port     = String.fromEnvironment('DB_PORT');
  static const dbName   = String.fromEnvironment('DB_NAME');
  static const user     = String.fromEnvironment('DB_USER');
  static const pass     = String.fromEnvironment('DB_PASS');
}
