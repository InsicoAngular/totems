// lib/models/cupos_info.dart
import 'package:flutter/material.dart';

class CuposInfo {
  final bool habilitado;
  final int cupos;
  final TimeOfDay inicio;
  final TimeOfDay fin;
  final String motivo;

  const CuposInfo({
    required this.habilitado,
    required this.cupos,
    required this.inicio,
    required this.fin,
    this.motivo = 'OK',
  });

  factory CuposInfo.fromJson(Map<String, dynamic> j) {
    TimeOfDay _parseTod(dynamic v) {
      if (v == null) return const TimeOfDay(hour: 0, minute: 0);
      final s = v.toString();
      final parts = s.split(':');
      if (parts.length < 2) return const TimeOfDay(hour: 0, minute: 0);
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      return TimeOfDay(hour: h, minute: m);
    }

    // Acepta nombres alternativos del backend
    final ini = j['inicio'] ?? j['horaInicio'];
    final fin = j['fin'] ?? j['horaTermino'];

    final habil =
        (j['habilitado'] == true) || (j['habilitado'] == 1) || (j['activo'] == 1);

    final disponibles = (j['disponibles'] ?? j['cupos'] ?? 0);
    final cuposInt = disponibles is int ? disponibles : int.tryParse('$disponibles') ?? 0;

    return CuposInfo(
      habilitado: habil,
      cupos: cuposInt,
      inicio: _parseTod(ini),
      fin: _parseTod(fin),
      motivo: (j['motivo'] ?? 'OK').toString(),
    );
  }
}
