import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/database_config.dart';
import '../models/reserva.dart';
import '../models/practico_result.dart';
import '../models/insert_result.dart';
import '../services/database_service.dart';

final reservaProvider = FutureProvider.family<Object?, String>((
  ref,
  rut,
) async {
  return DatabaseService.instance.fetchReserva(rut);
});

final insertProvider = FutureProvider.autoDispose
    .family<InsertResult, Map<String, String>>((ref, data) async {
      final rut = data['rut'] ?? '';
      final code = data['code'] ?? 'XX';
      return DatabaseService.instance.fetchAndInsert(rut, code);
    });

final practicoResultProvider = FutureProvider.family<PracticoResult?, String>((
  ref,
  rut,
) async {
  if (DatabaseConfig.practico) return null;
  return await DatabaseService.instance.fetchReserva(rut) as PracticoResult?;
});

final reservaLicenciasProvider = FutureProvider.family<Reserva?, String>((
  ref,
  rut,
) async {
  if (DatabaseConfig.practico) return null;
  return await DatabaseService.instance.fetchReserva(rut) as Reserva?;
});
