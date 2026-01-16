// lib/providers/cupos_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cupos_info.dart';
import '../services/database_service.dart';

final cuposProvider = FutureProvider.family<CuposInfo, String>((ref, labelTramite) async {
  final c = await DatabaseService.instance.checkCupoManualPorLabel(labelTramite: labelTramite);

  return CuposInfo.fromJson({
    'habilitado': c.ok ? 1 : 0,
    'disponibles': c.disponibles,
    'horaInicio': c.horaInicio,     // "HH:mm:ss"
    'horaTermino': c.horaTermino,   // "HH:mm:ss"
    'motivo': c.motivo,
  });
});
