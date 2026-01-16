// lib/screens/error_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_header.dart';

class ErrorScreen extends StatefulWidget {
  const ErrorScreen({Key? key}) : super(key: key);

  @override
  State<ErrorScreen> createState() => _ErrorScreenState();
}

class _ErrorScreenState extends State<ErrorScreen> {
  static const int _startSeconds = 5;
  late int _secondsRemaining;
  Timer? _timer;

  // Colores dinámicos de botones
  Color _buttonBg = Colors.deepPurple;
  Color _buttonFg = Colors.white;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = _startSeconds;
    _loadButtonColors();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) {
        timer.cancel();
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  Future<void> _loadButtonColors() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _buttonBg = Color(prefs.getInt('buttonBg') ?? Colors.deepPurple.value);
      _buttonFg = Color(prefs.getInt('buttonText') ?? Colors.white.value);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments;
    final message = args is String ? args : 'Ha ocurrido un error inesperado';

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppHeader(),
            const SizedBox(height: 32),
            Icon(Icons.error_outline, size: 96, color: Colors.red[700]),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Oops!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.red[700],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                message,
                style: const TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
            ),
            const Spacer(),
            Center(
              child: Text(
                'Volviendo en ${_secondsRemaining} s',
                style: const TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  _timer?.cancel();
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/',
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.home),
                label: const Text('Volver al inicio ahora'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _buttonBg,
                  foregroundColor: _buttonFg,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
