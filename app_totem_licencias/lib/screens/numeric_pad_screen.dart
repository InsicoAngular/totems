import 'dart:async';
import 'package:app_totem_licencias/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/database_config.dart';
import '../providers/reserva_providers.dart';
import '../models/etapa.dart';
import 'app_header.dart';

/// ===== Utils de RUT (independientes del State) =====
class RutUtils {
  static String clean(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^0-9K]'), '');

  static String dv(String body) {
    int sum = 0, mul = 2;
    for (int i = body.length - 1; i >= 0; i--) {
      sum += int.parse(body[i]) * mul;
      mul = (mul == 7) ? 2 : mul + 1;
    }
    final res = 11 - (sum % 11);
    if (res == 11) return '0';
    if (res == 10) return 'K';
    return res.toString();
  }

  static bool isValid(String raw) {
    final c = clean(raw);
    if (c.length < 2) return false;
    final body = c.substring(0, c.length - 1);
    final check = c.substring(c.length - 1);
    if (!RegExp(r'^\d{1,8}$').hasMatch(body)) return false; // 1..8 dígitos
    return dv(body) == check;
  }

  static String format(String raw) {
    final c = clean(raw);
    if (c.isEmpty) return '';
    final body = c.substring(0, c.length - 1);
    final check = c.substring(c.length - 1);
    return '$body-$check';
  }
}

class NumericPadScreen extends ConsumerStatefulWidget {
  const NumericPadScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<NumericPadScreen> createState() => _NumericPadScreenState();
}

class _NumericPadScreenState extends ConsumerState<NumericPadScreen> {
  String _rawRut = '';
  bool _isLoading = false;
  Color _buttonBg = Colors.deepPurple;
  Color _buttonFg = Colors.white;

  // ✅ Getters que usan la utilidad y ven _rawRut correctamente
  String get _formattedRut => RutUtils.format(_rawRut);
  bool get _rutValido => RutUtils.isValid(_rawRut);

  double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  @override
  void initState() {
    super.initState();
    _loadButtonColors();
  }

  Future<void> _loadButtonColors() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _buttonBg = Color(prefs.getInt('buttonBg') ?? Colors.deepPurple.value);
      _buttonFg = Color(prefs.getInt('buttonText') ?? Colors.white.value);
    });
  }

  /*──────── teclado ────────*/
  void _onKeyTap(String key) {
    setState(() {
      switch (key) {
        case 'DEL':
        case 'CLR':
          if (_rawRut.isNotEmpty) {
            _rawRut = _rawRut.substring(0, _rawRut.length - 1);
          }
          break;
        case 'K':
          if (_rawRut.isEmpty) return; // no parte con K
          if (_rawRut.toUpperCase().contains('K')) return; // una sola K
          if (_rawRut.length < 9) _rawRut += 'K'; // K al final
          break;
        default: // dígito
          if (_rawRut.toUpperCase().endsWith('K')) return; // no después de K
          if (_rawRut.length < 9) _rawRut += key;
      }
    });
  }

  void _onKeyLongPress(String key) {
    if (key == 'CLR') setState(() => _rawRut = '');
  }

  /*──────── consultar ────────*/
  Future<void> _consultar() async {
    final rut = _formattedRut;
    if (rut.length < 3) return; // cuerpo + '-' + dv

    if (rut != '999-9' && !_rutValido) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('RUT inválido. Verifica número y dígito.'),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(Duration.zero);

    try {
      final args =
          (ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?) ??
          {};

      final rawMode = (args['flow'] ?? args['modo']) as String?;
      final flow = switch ((rawMode ?? '').toLowerCase()) {
        'online' => 'online',
        'practico' => 'practico',
        _ => 'alca',
      };

      final label = (args['label'] ?? args['tramite']) as String?;
      final cupoId = args['cupoId'] as int?;

      if (flow == 'practico') {
        // Valida etapas en ResultScreen; ahí se emite ticket si corresponde
        Navigator.pushNamed(
          context,
          '/result',
          arguments: {'rut': rut, 'flow': 'practico'},
        );
        return;
      }

      if (flow == 'alca') {
        // MANUAL/ALC: deja a ResultScreen llamar emitirPorBoton(label) y consumir cupo
        Navigator.pushNamed(
          context,
          '/result',
          arguments: {
            'flow': 'alca',
            'rut': rut,
            'label':
                label, // nombre visible del botón (igual a ALCBotonesTotem.tramite)
            'cupoId': cupoId, // opcional: bloque ya elegido
          },
        );
        return;
      }

      // ONLINE
      Navigator.pushNamed(
        context,
        '/result',
        arguments: {'rut': rut, 'flow': 'online'},
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/error', arguments: e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /*──────── UI ────────*/
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final numericKeys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      'K',
      '0',
      'CLR',
    ];

    final args =
        (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?) ??
        {};
    final flow = (args['flow'] as String?) ?? 'alca';
    final label = args['label'] as String?;

    final displayH = _clamp(size.height * 0.16, 120, 220);
    final displayFS = _clamp(size.width * 0.09, 42, 90);
    final actionH = _clamp(size.height * 0.095, 76, 110);
    final hPad = _clamp(size.width * 0.02, 12, 24);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(),

            // DISPLAY RUT (con feedback visual)
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 8),
              child: Column(
                children: [
                  Container(
                    height: displayH,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                      border:
                          (_formattedRut.isEmpty)
                              ? null
                              : Border.all(
                                color:
                                    (_formattedRut == '999-9' || _rutValido)
                                        ? Colors.green
                                        : Colors.red,
                                width: 3,
                              ),
                      boxShadow: [
                        if (_formattedRut.isNotEmpty)
                          BoxShadow(
                            color: (_formattedRut == '999-9' || _rutValido
                                    ? Colors.green
                                    : Colors.red)
                                .withOpacity(0.15),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _formattedRut.isEmpty
                            ? '— — — — — — — — —'
                            : _formattedRut,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: displayFS,
                          letterSpacing: 3,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF111827),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_formattedRut.isNotEmpty &&
                      _formattedRut != '999-9' &&
                      !_rutValido)
                    const Text(
                      'RUT inválido',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),

            // TECLADO
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: Column(
                  children: [
                    for (var row = 0; row < 4; row++)
                      Expanded(
                        child: Row(
                          children: [
                            for (var col = 0; col < 3; col++)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final side =
                                          constraints.biggest.shortestSide;
                                      final fs = side * 0.5;
                                      final labelKey =
                                          numericKeys[row * 3 + col];
                                      return InkWell(
                                        onTap: () => _onKeyTap(labelKey),
                                        onLongPress:
                                            () => _onKeyLongPress(labelKey),
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          width: side,
                                          height: side,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            border: Border.all(
                                              color: Colors.grey.shade400,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              labelKey,
                                              style: TextStyle(
                                                fontSize: fs,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // BOTONES ACCIÓN
            Padding(
              padding: EdgeInsets.fromLTRB(
                hPad,
                0,
                hPad,
                _clamp(size.height * 0.02, 12, 24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: actionH,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() => _rawRut = ''),
                        icon: const Icon(
                          Icons.delete_forever_rounded,
                          size: 28,
                        ),
                        label: const Text('BORRAR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _buttonBg,
                          foregroundColor: _buttonFg,
                          elevation: 6,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: actionH,
                      child: ElevatedButton.icon(
                        onPressed:
                            () => Navigator.pushNamedAndRemoveUntil(
                              context,
                              '/',
                              (_) => false,
                            ),
                        icon: const Icon(Icons.home_rounded, size: 28),
                        label: const Text('INICIO'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _buttonBg,
                          foregroundColor: _buttonFg,
                          elevation: 6,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: actionH,
                      child: ElevatedButton.icon(
                        onPressed:
                            (_isLoading ||
                                    (!_rutValido && _formattedRut != '999-9'))
                                ? null
                                : () => _consultar(),
                        icon:
                            _isLoading
                                ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                )
                                : const Icon(
                                  Icons.check_circle_rounded,
                                  size: 28,
                                ),
                        label: const Text('OK'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _buttonBg,
                          foregroundColor: _buttonFg,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade600,
                          elevation: 6,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
