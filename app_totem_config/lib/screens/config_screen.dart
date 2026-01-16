import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/totem_config.dart';
import '../services/database_service.dart';

class ConfigScreen extends StatefulWidget {
  final int totemId;
  const ConfigScreen({Key? key, required this.totemId}) : super(key: key);

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late SharedPreferences _prefs;
  bool _isLoading = true;
  bool _isSaving = false;

  final _welcomeCtrl   = TextEditingController();
  final _hashtagCtrl   = TextEditingController();
  final _marqueeCtrl   = TextEditingController();
  final _assetsDirCtrl = TextEditingController();

  Color _buttonBgColor   = Colors.deepPurple;
  Color _buttonTextColor = Colors.white;
  int   _waitingLayout   = 1;
  bool  _isWaitingScreen = false;

  // Valor por defecto si el campo de ruta queda vacío
  static const String _defaultAssetsDir = r'C:\Insico\assets\';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _welcomeCtrl.dispose();
    _hashtagCtrl.dispose();
    _marqueeCtrl.dispose();
    _assetsDirCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      setState(() => _isLoading = true);
    
      _prefs = await SharedPreferences.getInstance();

      // 1) Intentar cargar desde SQL Server
      final db = await DatabaseService.instance.fetchConfig(
        totemId: widget.totemId,
      );
    
      if (db != null) {
        final map = json.decode(db['json'] as String) as Map<String, dynamic>;
        final cfg = TotemConfig.fromMap(map);
        setState(() {
          _welcomeCtrl.text    = cfg.welcomeText;
          _hashtagCtrl.text    = cfg.hashtag;
          _marqueeCtrl.text    = cfg.marqueeText;
          _buttonBgColor       = Color(cfg.buttonBg);
          _buttonTextColor     = Color(cfg.buttonText);
          _assetsDirCtrl.text  = cfg.assetsDir.isNotEmpty
              ? cfg.assetsDir
              : _defaultAssetsDir;
          _waitingLayout       = cfg.waitingLayout;
          _isWaitingScreen     = cfg.isWaitingScreen;
        });
        return;
      }

      // 2) Fallback a SharedPreferences
      setState(() {
        _welcomeCtrl.text    = _prefs.getString('welcomeText')  ?? '';
        _hashtagCtrl.text    = _prefs.getString('hashtag')      ?? '';
        _marqueeCtrl.text    = _prefs.getString('marqueeText')  ?? '';
        _buttonBgColor       = Color(_prefs.getInt('buttonBg')    ?? Colors.deepPurple.value);
        _buttonTextColor     = Color(_prefs.getInt('buttonText')  ?? Colors.white.value);
        final savedAssets    = _prefs.getString('assetsDir')     ?? '';
        _assetsDirCtrl.text  = savedAssets.isNotEmpty
            ? savedAssets
            : _defaultAssetsDir;
        _waitingLayout       = _prefs.getInt('waitingLayout')    ?? 1;
        _isWaitingScreen     = _prefs.getBool('isWaitingScreen') ?? false;
      });
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error al cargar configuración: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickColor(bool isBg) async {
    final theme = Theme.of(context);
    final current = isBg ? _buttonBgColor : _buttonTextColor;
  
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.palette_rounded,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(isBg ? 'Color de Fondo' : 'Color de Texto'),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: BlockPicker(
            pickerColor: current,
            availableColors: [
              Colors.black, Colors.white, Colors.deepPurple,
              Colors.blue, Colors.green, Colors.red,
              Colors.orange, Colors.teal, Colors.purple,
              Colors.indigo, Colors.cyan, Colors.pink,
            ],
            onColorChanged: (c) {
              setState(() {
                if (isBg) _buttonBgColor = c;
                else      _buttonTextColor = c;
              });
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
  
    try {
      setState(() => _isSaving = true);

      // Si el usuario no pone ruta, tomamos el default
      final assetsDirValue = _assetsDirCtrl.text.trim().isNotEmpty
          ? _assetsDirCtrl.text.trim()
          : _defaultAssetsDir;

      final cfg = TotemConfig(
        welcomeText:     _welcomeCtrl.text,
        hashtag:         _hashtagCtrl.text,
        marqueeText:     _marqueeCtrl.text,
        buttonBg:        _buttonBgColor.value,
        buttonText:      _buttonTextColor.value,
        assetsDir:       assetsDirValue,
        waitingLayout:   _waitingLayout,
        isWaitingScreen: _isWaitingScreen,
      );

      // 1) Guardar en SQL Server
      await DatabaseService.instance.upsertConfig(
        totemId:    widget.totemId,
        configJson: json.encode(cfg.toMap()),
      );

      // 2) Guardar en SharedPreferences
      await _prefs
        ..setString('welcomeText',    cfg.welcomeText)
        ..setString('hashtag',        cfg.hashtag)
        ..setString('marqueeText',    cfg.marqueeText)
        ..setInt('buttonBg',          cfg.buttonBg)
        ..setInt('buttonText',        cfg.buttonText)
        ..setString('assetsDir',      assetsDirValue)
        ..setInt('waitingLayout',     cfg.waitingLayout)
        ..setBool('isWaitingScreen',  cfg.isWaitingScreen);

      if (mounted) {
        _showSuccessSnackBar('Configuración guardada exitosamente');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error al guardar: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: theme.colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: theme.colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuración',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Tótem #${widget.totemId}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onPrimary.withOpacity(0.8),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton.filled(
              icon: _isSaving 
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              tooltip: 'Guardar Configuración',
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.onPrimary.withOpacity(0.1),
                foregroundColor: colorScheme.onPrimary,
              ),
              onPressed: _isSaving ? null : _save,
            ),
          ),
        ],
      ),
      body: _isLoading 
          ? _buildLoadingState(context)
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildGeneralSection(context),
                    const SizedBox(height: 24),
                    if (_isWaitingScreen) 
                      _buildWaitingScreenSection(context)
                    else 
                      _buildTotemSection(context),
                    const SizedBox(height: 32),
                    _buildSaveButton(context),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Cargando configuración...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings_rounded,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Configuración General',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              title: Text(
                'Pantalla de Espera',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                'Activar configuración para pantalla de espera',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              value: _isWaitingScreen,
              onChanged: (v) => setState(() => _isWaitingScreen = v),
              activeColor: colorScheme.primary,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            Text(
              'Ruta de Assets',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _assetsDirCtrl,
              decoration: InputDecoration(
                hintText: _defaultAssetsDir,
                prefixIcon: const Icon(Icons.folder_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingScreenSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.hourglass_empty_rounded,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Pantalla de Espera',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Diseño de Layout',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.view_module_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
              ),
              value: _waitingLayout,
              items: const [
                DropdownMenuItem(
                  value: 1, 
                  child: Text('Layout 1 – Clásico'),
                ),
                DropdownMenuItem(
                  value: 2, 
                  child: Text('Layout 2 – Grid'),
                ),
                DropdownMenuItem(
                  value: 3, 
                  child: Text('Layout 3 – Lista Grande'),
                ),
              ],
              onChanged: (v) => setState(() => _waitingLayout = v ?? 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotemSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.router_rounded,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Configuración del Tótem',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildTextField(
              'Texto de Bienvenida',
              _welcomeCtrl,
              Icons.waving_hand_rounded,
              'Ej: ¡Bienvenido!',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              'Hashtag',
              _hashtagCtrl,
              Icons.tag_rounded,
              'Ej: #MiEvento2024',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              'Mensaje del Tótem',
              _marqueeCtrl,
              Icons.message_rounded,
              'Mensaje que se mostrará en el tótem',
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            _buildColorSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon,
    String hint, {
    int maxLines = 1,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
          ),
        ),
      ],
    );
  }

  Widget _buildColorSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Colores del Botón',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildColorButton(
                'Fondo',
                _buttonBgColor,
                Icons.format_color_fill_rounded,
                () => _pickColor(true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildColorButton(
                'Texto',
                _buttonTextColor,
                Icons.format_color_text_rounded,
                () => _pickColor(false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColorButton(
    String label,
    Color color,
    IconData icon,
    VoidCallback onPressed,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: color.computeLuminance() > 0.5 
                      ? Colors.black 
                      : Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Cambiar',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color.computeLuminance() > 0.5 
                        ? Colors.black 
                        : Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FilledButton(
      onPressed: _isSaving ? null : _save,
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _isSaving
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Guardando...'),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.save_rounded),
                const SizedBox(width: 12),
                Text(
                  'Guardar Configuración',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
    );
  }
}