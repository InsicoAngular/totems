// lib/app_header.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:marquee/marquee.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppHeader extends StatefulWidget {
  const AppHeader({
    super.key,
    this.tickerHeight = 72, // grosor barra superior
    this.brandHeight = 170, // alto franja de marca
    this.logoMaxHeight = 140, // tamaño del logo
    this.hashtagFontSize = 20, // tamaño hashtag
    this.marqueeFontSize = 20, // tamaño marquee
  });

  final double tickerHeight;
  final double brandHeight;
  final double logoMaxHeight;
  final double hashtagFontSize;
  final double marqueeFontSize;

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  String _hash = '#CualquierMuni';
  String _marq = 'TOTEM ATENCIÓN LICENCIAS DE CONDUCIR';
  File? _logoFile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pfs = await SharedPreferences.getInstance();
    setState(() {
      _hash = pfs.getString('hashtag') ?? _hash;
      _marq = pfs.getString('marqueeText') ?? _marq;

      final dir = pfs.getString('assetsDir') ?? r'C:\Insico\assets\';
      final f = File(p.join(dir, 'logo.png'));
      if (f.existsSync()) _logoFile = f;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Barra superior gruesa
        Container(
          height: widget.tickerHeight,
          color: const Color(0xFF2C333A),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                _hash,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.hashtagFontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ClipRect(
                  child: Marquee(
                    text: _marq,
                    velocity: 35,
                    blankSpace: 80,
                    startPadding: 8,
                    startAfter: const Duration(milliseconds: 400),
                    pauseAfterRound: const Duration(milliseconds: 0),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.marqueeFontSize,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Franja de marca / logo grande
        Container(
          height: widget.brandHeight,
          color: cs.surface,
          alignment: Alignment.center,
          child:
              _logoFile != null
                  ? Image.file(
                    _logoFile!,
                    height: widget.logoMaxHeight,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  )
                  : Image.asset(
                    'assets/logo.png',
                    height: widget.logoMaxHeight,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
        ),
      ],
    );
  }
}
