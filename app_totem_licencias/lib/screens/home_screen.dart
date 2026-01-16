import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/reserva_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _rawRut = '';
  bool _isLoading = false;

  void _onKeyTap(String key) {
    setState(() {
      if (key == 'DEL') {
        if (_rawRut.isNotEmpty)
          _rawRut = _rawRut.substring(0, _rawRut.length - 1);
      } else if (key == 'CLR') {
        _rawRut = '';
      } else if (_rawRut.length < 9) {
        _rawRut += key;
      }
    });
  }

  String get _formattedRut {
    final clean = _rawRut.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length <= 1) return clean;
    final body = clean.substring(0, clean.length - 1);
    final dv = clean.substring(clean.length - 1).toUpperCase();
    return '$body-$dv';
  }

  Future<void> _consultar() async {
    final rut = _formattedRut;
    if (rut.length < 2) return;

    setState(() => _isLoading = true);
    try {
      final insertResult = await ref.read(
        insertProvider({'rut': rut, 'code': 'ON'}).future,
      );
      if (!mounted) return;

      if (insertResult.success) {
        Navigator.pushNamed(
          context,
          '/result',
          arguments: rut, // pasamos el rut a la siguiente pantalla
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('RUT no encontrado o error')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildKey(String label, double keySize, double fontSize) {
    return InkWell(
      onTap: () => _onKeyTap(label),
      borderRadius: BorderRadius.circular(keySize * 0.1),
      child: Container(
        height: keySize,
        width: keySize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border.all(color: Colors.grey[400]!),
          borderRadius: BorderRadius.circular(keySize * 0.1),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final margin = w * 0.04;
    final displayH = h * 0.15;
    final keypadH = h * 0.60;
    final buttonH = h * 0.20;
    final gapH = h * 0.05 / 4;

    final contentW = w - margin * 2;
    final spacing = contentW * 0.02;
    final keySize = min(
      (contentW - spacing * 2) / 3,
      (keypadH - spacing * 3) / 4,
    );
    final keyFont = keySize * 0.4;
    final buttonFont = buttonH * 0.4;
    final displayFont = displayH * 0.5;
    final keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      'DEL',
      '0',
      'CLR',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tótem de Licencias'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: gapH),
            // DISPLAY
            SizedBox(
              height: displayH,
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: margin),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(displayH * 0.1),
                ),
                alignment: Alignment.center,
                child: Text(
                  _formattedRut.isEmpty ? '– – – – – – – – –' : _formattedRut,
                  style: TextStyle(
                    fontSize: displayFont,
                    letterSpacing: displayFont * 0.05,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(height: gapH),
            // KEYPAD
            SizedBox(
              height: keypadH,
              child: Center(
                child: SizedBox(
                  width: keySize * 3 + spacing * 2,
                  height: keySize * 4 + spacing * 3,
                  child: GridView.count(
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    children: [
                      for (final k in keys) _buildKey(k, keySize, keyFont),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: gapH),
            // BOTÓN CONSULTAR
            SizedBox(
              height: buttonH,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                child: ElevatedButton(
                  onPressed:
                      (_isLoading || _formattedRut.length < 2)
                          ? null
                          : _consultar,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(buttonH * 0.1),
                    ),
                  ),
                  child:
                      _isLoading
                          ? SizedBox(
                            height: buttonH * 0.5,
                            width: buttonH * 0.5,
                            child: const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          )
                          : Text(
                            'Consultar',
                            style: TextStyle(
                              fontSize: buttonFont,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                ),
              ),
            ),
            SizedBox(height: gapH),
          ],
        ),
      ),
    );
  }
}
