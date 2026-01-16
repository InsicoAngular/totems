// lib/models/totem_info.dart
import 'profile.dart';

class TotemInfo {
  final int totemId;
  final int municipalidadId;
  final String code;
  final String nombreMuni;
  final Profile profile;
  TotemInfo({
    required this.totemId,
    required this.municipalidadId,
    required this.code,
    required this.nombreMuni,
    required this.profile,
  });
}