// lib/widgets/app_header.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Header de la app que muestra únicamente el logo.
class AppHeader extends StatefulWidget {
  const AppHeader({Key? key}) : super(key: key);

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  String? _logoPath;

  @override
  void initState() {
    super.initState();
    _loadLogoPath();
  }

  Future<void> _loadLogoPath() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _logoPath = prefs.getString('logoPath');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      child: _logoPath != null
          ? Image.file(File(_logoPath!), height: 80)
          : Image.asset('assets/logo.png', height: 80),
    );
  }
}
