// lib/models/etapa.dart
class Etapa {
  final int id;          // 880…889
  final String nombre;   // CAJA, FOTOGRAFÍA…
  final String resultado;
  const Etapa(this.id, this.nombre, this.resultado);

  bool get pendiente =>
      id <= 885 && (resultado == 'E' || resultado == 'S');
}
