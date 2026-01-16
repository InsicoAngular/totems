// lib/models/atencion.dart
class Atencion {
  final int id;
  final String fecha;           // yyyymmdd
  final String tipo;            // P/R/J/…
  final String correlativo;     // L28_CORRELATIVO
  final String numRut;          // solo números
  final String? hora;           // hhmmss
  final String? asignado;       // 'S'/'N'/null
  final String? atendido;       // 'S'/'N'/null
  final String? nombres;
  final String? apellidos;
  final String? numSol;         // puede venir null
  final String? correlativo1;   // opcional

  Atencion({
    required this.id,
    required this.fecha,
    required this.tipo,
    required this.correlativo,
    required this.numRut,
    this.hora,
    this.asignado,
    this.atendido,
    this.nombres,
    this.apellidos,
    this.numSol,
    this.correlativo1,
  });

  factory Atencion.fromJson(Map<String, dynamic> m) => Atencion(
    id           : (m['id'] ?? 0) as int,
    fecha        : (m['L28_FECHA'] ?? '').toString(),
    tipo         : (m['L28_TIPO'] ?? '').toString(),
    correlativo  : (m['L28_CORRELATIVO'] ?? '').toString(),
    numRut       : (m['L28_NUMRUT'] ?? '').toString(),
    hora         : (m['L28_HORA'] as String?) ,
    asignado     : (m['L28_ASIGNADO'] as String?) ,
    atendido     : (m['L28_ATENDIDO'] as String?) ,
    nombres      : (m['L28_NOMBRES'] as String?) ,
    apellidos    : (m['L28_APELLIDOS'] as String?) ,
    numSol       : (m['L28_NUMSOL'] as String?) ,
    correlativo1 : (m['L28_CORRELATIVO1'] as String?) ,
  );
}
