// lib/models/municipality.dart
class Municipality {
  final int id;
  final String name;
  final int totemCount;  // número de tótems asociados

  Municipality({
    required this.id,
    required this.name,
    required this.totemCount,
  });
}
