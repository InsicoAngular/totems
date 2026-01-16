// lib/screens/tramites_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ⬅️ nuevo
import '../screens/app_header.dart';
import '../config/database_config.dart';
import '../services/database_service.dart';

class TramitesScreen extends StatefulWidget {
  // ⬅️ era Stateless
  const TramitesScreen({super.key});

  @override
  State<TramitesScreen> createState() => _TramitesScreenState();
}

class _TramitesScreenState extends State<TramitesScreen> {
  Color _btnBg = Colors.deepPurple;
  Color _btnFg = Colors.white;

  @override
  void initState() {
    super.initState();
    _loadBrandColors();
  }

  Future<void> _loadBrandColors() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _btnBg = Color(p.getInt('buttonBg') ?? Colors.deepPurple.value);
      _btnFg = Color(p.getInt('buttonText') ?? Colors.white.value);
    });
  }

  static const String kOnlineLabel = 'SOLICITUD POR INTERNET';

  void _goBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  @override
  Widget build(BuildContext context) {
    if (DatabaseConfig.practico) {
      // Para operador en PC (sin keypad)
      Future.microtask(() {
        Navigator.pushReplacementNamed(context, '/practico-ops');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final size = MediaQuery.of(context).size;

    final isPortrait = size.height >= size.width;
    final maxContentWidth = _clamp(size.width * 0.92, 520, 760);
    final buttonHeight = _clamp(
      size.height * (isPortrait ? 0.09 : 0.12),
      72,
      110,
    );
    final fontSize = _clamp(size.width * 0.04, 22, 28);
    final gap = _clamp(size.height * 0.016, 12, 20);
    final hPad = _clamp(size.width * 0.02, 12, 24);

    final List<String> labels = [...DatabaseConfig.tramiteLabels, kOnlineLabel];

    Widget buildBtn(String label) {
      final esOnline = label.toUpperCase() == kOnlineLabel;
      final tipoEsperado = esOnline ? null : DatabaseConfig.tipoByLabel(label);

      return Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: SizedBox(
            height: buttonHeight,
            child: ElevatedButton(
              onPressed: () async {
                if (esOnline) {
                  Navigator.pushNamed(
                    context,
                    '/pad',
                    arguments: {'flow': 'online', 'code': 'ON'},
                  );
                } else {
                  // loader
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder:
                        (_) => const Center(child: CircularProgressIndicator()),
                  );

                  // verifica cupos por label exacto
                  final chk = await DatabaseService.instance
                      .checkCupoManualPorLabel(
                        labelTramite: label,
                        requiereApertura: false,
                      );

                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).pop(); // cierra loader

                  if (!chk.ok) {
                    await _showCuposDialog(
                      context,
                      tramite: label,
                      motivo: chk.motivo,
                      horaInicio: chk.horaInicio,
                      horaTermino: chk.horaTermino,
                      disponibles: chk.disponibles,
                      brandBg: _btnBg, // ⬅️ usa colores de BD
                      brandFg: _btnFg,
                    );
                    return;
                  }

                  Navigator.pushNamed(
                    context,
                    '/pad',
                    arguments: {
                      'flow': 'alca',
                      'code': tipoEsperado ?? DatabaseConfig.defaultTipo,
                      'label': label,
                      'cupoId': chk.cupoId,
                      'stock': chk.disponibles,
                    },
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _btnBg, // ⬅️ color de BD
                foregroundColor: _btnFg, // ⬅️ color de BD
                elevation: 10,
                shadowColor: _btnBg.withOpacity(0.35), // ⬅️ sombra acorde
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                minimumSize: Size.fromHeight(buttonHeight),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(),
            SizedBox(height: gap),

            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < labels.length; i++) ...[
                                buildBtn(labels[i]),
                                if (i != labels.length - 1)
                                  SizedBox(height: gap),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // VOLVER con borde usando brand
            Padding(
              padding: EdgeInsets.fromLTRB(
                hPad,
                0,
                hPad,
                _clamp(size.height * 0.02, 12, 24),
              ),
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: SizedBox(
                    height: _clamp(buttonHeight * 0.85, 60, 96),
                    child: OutlinedButton.icon(
                      onPressed: () => _goBack(context),
                      icon: const Icon(Icons.arrow_back),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'VOLVER',
                          style: TextStyle(
                            fontSize: _clamp(fontSize, 20, 26),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _btnBg,
                          width: 2,
                        ), // ⬅️ usa brand
                        foregroundColor: _btnBg, // ⬅️ usa brand
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // al final de lib/screens/tramites_screen.dart (o en un util)
  Future<void> _showCuposDialog(
    BuildContext context, {
    required String tramite,
    required String motivo,
    required String horaInicio, // "HH:mm:ss"
    required String horaTermino,
    int? disponibles,
    Color? brandBg, // ⬅️ nuevo
    Color? brandFg, // ⬅️ nuevo
  }) async {
    String _fmt(String hhmmss) =>
        hhmmss.length >= 5 ? hhmmss.substring(0, 5) : hhmmss;

    final cs = Theme.of(context).colorScheme;
    final Color bg = brandBg ?? cs.primary; // ⬅️ usa brand si viene
    final Color fg = brandFg ?? cs.onPrimary;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.outline.withOpacity(.15)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header con color de marca
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.info_rounded, size: 56, color: fg),
                      const SizedBox(height: 10),
                      Text(
                        'Información de cupos',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Chip del trámite
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: fg.withOpacity(.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          tramite.toUpperCase(),
                          style: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(
                            color: Colors.white, // contraste invertido
                            fontWeight: FontWeight.w700,
                            letterSpacing: .8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Contenido
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        motivo,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (horaInicio != '00:00:00' && horaTermino != '00:00:00')
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceVariant.withOpacity(.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cs.outline.withOpacity(.15),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.access_time_rounded, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Horario: ${_fmt(horaInicio)} – ${_fmt(horaTermino)}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      if (disponibles != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Disponibles: ${disponibles! < 0 ? 0 : disponibles}',
                          style: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(
                            color: bg,
                            fontWeight: FontWeight.w800, // usa brand
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Acciones con brand
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Volver'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: bg, width: 2),
                            foregroundColor: bg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: const Text('Entendido'),
                          style: FilledButton.styleFrom(
                            backgroundColor: bg,
                            foregroundColor: fg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
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
      },
    );
  }
}
