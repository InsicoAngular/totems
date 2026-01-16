import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:app_totem_licencias_pantalla/services/tts_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ticket.dart';
import '../providers/tickets_provider.dart';
import '../widgets/call_card.dart';

/// Pantalla de espera configurable por tótem
class WaitingScreen extends ConsumerStatefulWidget {
  final bool disableTts;                             // <--- NUEVO
  const WaitingScreen({Key? key, this.disableTts = false}) : super(key: key);

  @override
  ConsumerState<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends ConsumerState<WaitingScreen>
    with TickerProviderStateMixin {
  late final TtsService _tts;
  late final AnimationController _animationController;
  late final AnimationController _pulseController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _pulseAnimation;

  int? _lastSpokenId;
  bool _isWaitingEnabled = false;
  int _layout = 1;
  String _assetsDir = '';

  // —— PREFERENCIAS TTS ——
  String _ttsLocale = 'es-ES';
  String _ttsVoiceName = '';
  double _ttsRate = 0.5;
  double _ttsPitch = 1.0;
  double _ttsVolume = 1.0;

  @override
  void initState() {
    super.initState();
    _tts = TtsService();
    _setupAnimations();

    // Carga prefs y luego inicializa TTS
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadConfig();   // carga prefs UI y TTS
      await _tts.init();
      if (mounted) {
  // SOLO para probar en el PC problema:
  // puedes comentar esta línea después de la prueba.
  // unawaited(_tts.debugSelfTestUI(context));
}
      _animationController.forward();
    });
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isWaitingEnabled = prefs.getBool('isWaitingScreen') ?? false;
      _layout = prefs.getInt('waitingLayout') ?? 1;
      _assetsDir = prefs.getString('assetsDir') ?? '';

      // TTS
      _ttsLocale = prefs.getString('ttsLocale') ?? 'es-ES';
      _ttsVoiceName = prefs.getString('ttsVoiceName') ?? '';
      _ttsRate = prefs.getDouble('ttsRate') ?? 0.5;
      _ttsPitch = prefs.getDouble('ttsPitch') ?? 1.0;
      _ttsVolume = prefs.getDouble('ttsVolume') ?? 1.0;
    });
  }

Future<void> _speak(Ticket t) async {
  try {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _tts.stop();

        final nombre = t.name.trim().isEmpty
            ? (t.isManual ? 'Llamado' : 'Siguiente usuario')
            : _tts.normalizePersonName(t.name);

        final stationSsml = _tts.stationToSsml(t.station.isEmpty ? 'Módulo 1' : t.station);
        final ssml = _tts.buildCallSsml(nombre: nombre, stationSsml: stationSsml);

        await _tts.speak(ssml);  // 👈 ahora mandamos SSML, no texto plano
      } catch (e) {
        debugPrint('TTS speak error: $e');
      }
    });
  } catch (_) {}
}

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    _tts.stop();
    _tts.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!_isWaitingEnabled) {
      return _buildDisabledScreen(context);
    }

    final asyncTickets = ref.watch(ticketsStreamProvider);
    ref.listen<AsyncValue<List<Ticket>>>(
      ticketsStreamProvider,
      (_, next) => next.whenData((tickets) {
        if (tickets.isNotEmpty && tickets.first.id != _lastSpokenId) {
          _lastSpokenId = tickets.first.id;
          _speak(tickets.first);
          _animationController.reset();
          _animationController.forward();
        }
      }),
    );

    return AnimatedBuilder(
      animation: _fadeAnimation,
      child: asyncTickets.when(
        loading: () => _LoadingScreen(logo: _logoWidget()),
        error: (e, _) => _ErrorScreen(
          error: e.toString(),
          logo: _logoWidget(),
          onRetry: () => ref.refresh(ticketsStreamProvider),
        ),
        data: (tickets) {
          if (tickets.isEmpty) {
            return _EmptyScreen(logo: _logoWidget());
          }
          switch (_layout) {
            case 2:
              return _Layout2(tickets: tickets, logo: _logoWidget());
            case 3:
              return _Layout3(tickets: tickets, logo: _logoWidget());
            default:
              return _Layout1(
                tickets: tickets,
                logo: _logoWidget(),
                pulseAnimation: _pulseAnimation,
              );
          }
        },
      ),
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - _fadeAnimation.value)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildDisabledScreen(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.surface,
              colorScheme.surfaceVariant.withOpacity(0.3),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tv_off_rounded,
                    size: 64,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pantalla de Espera Deshabilitada',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Esta funcionalidad está desactivada para este tótem',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Carga logo.png desde carpeta configurada o usa el asset por defecto
  Widget _logoWidget({double? width}) {
    final sep = Platform.pathSeparator;
    final base = _assetsDir.endsWith(sep) ? _assetsDir : '$_assetsDir$sep';
    final file = File('${base}logo.png');

    Widget logoImage;
    if (_assetsDir.isNotEmpty && file.existsSync()) {
      logoImage = Image.file(file, width: width, fit: BoxFit.contain);
    } else {
      logoImage = Image.asset('assets/logo.png', width: width, fit: BoxFit.contain);
    }

    return Hero(
      tag: 'logo',
      child: logoImage,
    );
  }
}

// justo antes o después de _Layout1, agrega este helper:
class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? bg;
  final Color? fg;
  const _Pill({required this.icon, required this.text, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgc = bg ?? cs.primary.withOpacity(.10);
    final fgc = fg ?? cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgc,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fgc.withOpacity(.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fgc),
          const SizedBox(width: 8),
          Text(text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: fgc,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                  )),
        ],
      ),
    );
  }
}


/// Layout 1: Clásico profesional con turno actual destacado y historial lateral
class _Layout1 extends StatelessWidget {
  final List<Ticket> tickets;
  final Widget logo;
  final Animation<double> pulseAnimation; // se mantiene para compat

  const _Layout1({
    required this.tickets,
    required this.logo,
    required this.pulseAnimation,
  });

  IconData _areaIconByCode(String t) {
    switch (t.toUpperCase()) {
      case 'M': return Icons.local_hospital_rounded;   // Médico
      case 'P': return Icons.psychology_rounded;       // Psicométrico
      case 'S': return Icons.groups_2_rounded;         // Social
      case 'U': return Icons.account_balance_rounded;  // Universal
      default:  return Icons.category_rounded;         // General
    }
  }

  String _examLabelFrom(String code) {
    switch (code.toUpperCase()) {
      case 'P': return 'Primera Vez';
      case 'R': return 'Renovación';
      case 'D': return 'Duplicado';
      default:  return '';
    }
  }

  IconData _examIcon(String code) {
    switch (code.toUpperCase()) {
      case 'P': return Icons.fiber_new_rounded;
      case 'R': return Icons.rotate_right_rounded;
      case 'D': return Icons.copy_all_rounded;
      default:  return Icons.assignment_turned_in_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final current = tickets.first;
final allHistory = tickets.length > 1 ? tickets.sublist(1) : <Ticket>[];
final history = (allHistory.length <= 2)
    ? allHistory
    : allHistory.sublist(allHistory.length - 2); // ⬅️ últimos 2

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primary.withOpacity(0.03),
              cs.secondary.withOpacity(0.02),
              cs.surface,
            ],
            stops: const [0.0, 0.3, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Patrón de fondo (se mantiene, pero SIN logo watermark)
            Positioned.fill(
              child: CustomPaint(
                painter: _GeometricPatternPainter(cs.primary.withOpacity(0.02)),
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ⬆️ LOGO ARRIBA Y CENTRADO
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 140),
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: logo,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // “Turno actual” bajo el logo
                    _buildAnimatedHeader(context, 'Turno Actual'),

                    const SizedBox(height: 20),

                    // Card principal (nombre/módulo más grandes)
                    _buildMainTicketCard(context, current),

                    const SizedBox(height: 22),

                    // Historial debajo del turno actual (máx 2)
                    _buildHistorySectionVertical(context, history),
                  ],
                ),
              ),
            ),

            // Indicador “En Vivo”
            _buildStatusIndicator(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 500),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, v, child) {
        return Transform.translate(
          offset: Offset(0, 16 * (1 - v)),
          child: Opacity(
            opacity: v,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withOpacity(0.10),
                    cs.primaryContainer.withOpacity(0.18),
                  ],
                ),
                border: Border.all(color: cs.primary.withOpacity(0.20), width: 1.2),
              ),
              child: Text(
                title.toUpperCase(),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainTicketCard(BuildContext context, Ticket ticket) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 700),
      tween: Tween(begin: 0.95, end: 1.0),
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            margin: EdgeInsets.zero,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: LinearGradient(
                  colors: [cs.surface, cs.surfaceVariant.withOpacity(0.22)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: cs.outline.withOpacity(0.10), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ⬆️ agrandar textos de la tarjeta (nombre/módulo)
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(textScaleFactor: 1.28),
                      child: LayoutBuilder(
                        builder: (context, c) => ConstrainedBox(
                          constraints: BoxConstraints(minWidth: c.maxWidth),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: c.maxWidth,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: CallCard(ticket: ticket, isSmall: false),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Por favor acérquese al módulo indicado',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ======= HISTORIAL VERTICAL (debajo) – MÁX 2 =======
  Widget _buildHistorySectionVertical(BuildContext context, List<Ticket> history) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: cs.secondaryContainer.withOpacity(0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.secondary.withOpacity(0.25), width: 1),
          ),
          child: Text(
            'Últimos turnos',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSecondaryContainer,
              letterSpacing: .3,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (history.isEmpty)
          _buildEmptyHistory(context)
        else
          Column(
  children: List.generate(history.length, (i) {
    final item = history[i];
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 350 + i * 120),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, v, _) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - v)),
          child: Padding(
            padding: EdgeInsets.only(bottom: i == history.length - 1 ? 0 : 10),
            child: _buildHistoryItem(context, item),
          ),
        ),
      ),
    );
  }),
),
      ],
    );
  }

  Widget _buildEmptyHistory(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: cs.outline),
          const SizedBox(height: 8),
          Text('Sin turnos pendientes',
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(BuildContext context, Ticket ticket) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final examText = _examLabelFrom(ticket.tipoEspera);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [cs.surfaceVariant.withOpacity(0.5), cs.surfaceVariant.withOpacity(0.18)],
        ),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        border: Border.all(color: cs.outline.withOpacity(.08)),
      ),
      child: Card(
        elevation: 0,
        color: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CallCard(ticket: ticket, isSmall: true),
              if (examText.isNotEmpty) const SizedBox(height: 6),
              const SizedBox(height: 8),
              _Pill(
                icon: Icons.meeting_room_rounded,
                text: '${ticket.module}',
                bg: cs.primary.withOpacity(.10),
                fg: cs.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      top: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.primary.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 8),
            Text('En Vivo',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onPrimaryContainer, fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Layout 2: Diseño de grilla limpio sin carousel
class _Layout2 extends StatefulWidget {
  final List<Ticket> tickets;
  final Widget logo;

  const _Layout2({required this.tickets, required this.logo});

  @override
  State<_Layout2> createState() => _Layout2State();
}

class _Layout2State extends State<_Layout2> with TickerProviderStateMixin {
  late AnimationController _floatingController;
  late Animation<double> _floatingAnimation;

  @override
  void initState() {
    super.initState();

    _floatingController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    _floatingAnimation = Tween<double>(
      begin: -8.0,
      end: 8.0,
    ).animate(CurvedAnimation(
      parent: _floatingController,
      curve: Curves.easeInOut,
    ));

    _floatingController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentTicket = widget.tickets.first;
    final upcomingTickets = widget.tickets.length > 1
        ? widget.tickets.sublist(1, math.min(widget.tickets.length, 5))
        : <Ticket>[];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withOpacity(0.06),
              colorScheme.surface,
              colorScheme.secondaryContainer.withOpacity(0.08),
            ],
            stops: const [0.0, 0.5, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Logo de fondo sutil
            AnimatedBuilder(
              animation: _floatingAnimation,
              builder: (context, child) {
                return Positioned.fill(
                  child: Center(
                    child: Transform.translate(
                      offset: Offset(
                        _floatingAnimation.value,
                        _floatingAnimation.value * 0.3,
                      ),
                      child: Opacity(
                        opacity: 0.03,
                        child: Transform.scale(
                          scale: 1.5,
                          child: widget.logo,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Header moderno
                    _buildGridHeader(context),

                    const SizedBox(height: 24),

                    // Contenido principal
                    Expanded(
                      child: Row(
                        children: [
                          // Ticket actual (60%)
                          Expanded(
                            flex: 6,
                            child: _buildCurrentTicketCard(
                                context, currentTicket),
                          ),

                          const SizedBox(width: 20),

                          // Próximos turnos (40%)
                          Expanded(
                            flex: 4,
                            child: _buildUpcomingSection(
                                context, upcomingTickets),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Indicador de estado
            _buildLiveIndicator(context),
          ],
        ),
      ),
    );
  }

  Widget _buildGridHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 800),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withOpacity(0.9),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.onPrimary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.grid_view_rounded,
                      color: colorScheme.onPrimary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Centro de Atención',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Gestión de turnos en tiempo real',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onPrimary.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Contador de turnos
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.onPrimary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${widget.tickets.length}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Turnos',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                colorScheme.onPrimary.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentTicketCard(BuildContext context, Ticket ticket) {

// ── etiqueta de examen según código
String _examLabelFrom(String code) {
  switch (code.toUpperCase()) {
    case 'P': return 'Primera Vez';
    case 'R': return 'Renovación';
    case 'D': return 'Duplicado';
    default:  return '';
  }
}

IconData _examIcon(String code) {
  switch (code.toUpperCase()) {
    case 'P': return Icons.fiber_new_rounded;
    case 'R': return Icons.rotate_right_rounded;
    case 'D': return Icons.copy_all_rounded;
    default:  return Icons.assignment_turned_in_rounded;
  }
}

    final theme = Theme.of(context);
    final examText = _examLabelFrom(ticket.tipoEspera);
    final colorScheme = theme.colorScheme;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 1000),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.9 + (0.1 * value),
          child: Opacity(
            opacity: value,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.primaryContainer.withOpacity(0.8),
                    colorScheme.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              child: Card(
                elevation: 0,
                color: Colors.transparent,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      // Badge principal
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary
                                  .withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.campaign_rounded,
                              color: colorScheme.onPrimary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'LLAMANDO AHORA',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Contenido del ticket
                      Expanded(
                        child: CallCard(ticket: ticket, isSmall: false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUpcomingSection(BuildContext context, List<Ticket> tickets) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // Header de próximos
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colorScheme.secondary.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.queue_rounded,
                color: colorScheme.onSecondaryContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Próximos Turnos',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Lista de próximos turnos
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: colorScheme.surface.withOpacity(0.7),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.1),
              ),
            ),
            child: tickets.isEmpty
                ? _buildEmptyUpcoming(context)
                : _buildUpcomingList(context, tickets),
          ),
        ),
      ],
    );
  }

  Widget _buildUpcomingList(BuildContext context, List<Ticket> tickets) {
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: tickets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        return TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 600 + (index * 150)),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(40 * (1 - value), 0),
              child: Opacity(
                opacity: value,
                child: _buildUpcomingCard(context, tickets[index], index),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUpcomingCard(BuildContext context, Ticket ticket, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            colorScheme.surface,
            colorScheme.surfaceVariant.withOpacity(0.4),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Card(
        elevation: 0,
        color: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Número de posición
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    '${index + 2}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Contenido del ticket
              Expanded(
                child: CallCard(ticket: ticket, isSmall: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyUpcoming(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 48,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Sin turnos pendientes',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Los próximos turnos aparecerán aquí',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLiveIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Positioned(
      top: 16,
      right: 16,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(seconds: 2),
        tween: Tween(begin: 0.0, end: 1.0),
        builder: (context, value, child) {
          return Transform.scale(
            scale: 0.8 + (0.2 * math.sin(value * math.pi * 4)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'EN VIVO',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Layout 3: Diseño asimétrico moderno
class _Layout3 extends StatelessWidget {
  final List<Ticket> tickets;
  final Widget logo;

  const _Layout3({required this.tickets, required this.logo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bigTicket = tickets[0];
    final smallTickets =
        tickets.length > 1 ? tickets.sublist(1, math.min(3, tickets.length)) : <Ticket>[];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.5,
            colors: [
              colorScheme.primary.withOpacity(0.05),
              colorScheme.surface,
              colorScheme.surfaceVariant.withOpacity(0.3),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Logo de fondo con efecto de profundidad
            Positioned(
              bottom: -100,
              right: -100,
              child: Opacity(
                opacity: 0.06,
                child: Transform.rotate(
                  angle: math.pi / 12,
                  child: Transform.scale(
                    scale: 2.0,
                    child: logo,
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Header estilizado
                    _buildAsymmetricHeader(context),

                    const SizedBox(height: 20),

                    // Layout principal
                    Expanded(
                      child: Row(
                        children: [
                          // Tarjeta principal (65%)
                          Expanded(
                            flex: 65,
                            child: _buildMainCard(context, bigTicket),
                          ),

                          const SizedBox(width: 20),

                          // Tarjetas secundarias (35%)
                          Expanded(
                            flex: 35,
                            child: _buildSecondaryCards(context, smallTickets),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAsymmetricHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.primary.withOpacity(0.8),
            colorScheme.secondary.withOpacity(0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 25,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.onPrimary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.dashboard_rounded,
              color: colorScheme.onPrimary,
              size: 32,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Panel de Atención',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Sistema de turnos en tiempo real',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimary.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard(BuildContext context, Ticket ticket) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 800),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.9 + (0.1 * value),
          child: Opacity(
            opacity: value,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.primaryContainer.withOpacity(0.7),
                    colorScheme.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                    spreadRadius: -5,
                  ),
                ],
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.2),
                  width: 2,
                ),
              ),
              child: Card(
                elevation: 0,
                color: Colors.transparent,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      // Badge de prioridad
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'TURNO ACTUAL',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Contenido del ticket
                      Expanded(
                        child: CallCard(ticket: ticket, isSmall: false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSecondaryCards(BuildContext context, List<Ticket> tickets) {
    return Column(
      children: [
        // Título de la sección
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Anteriores',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        // Tarjetas secundarias
        Expanded(
          child: tickets.isEmpty
              ? _buildEmptySecondary(context)
              : Column(
                  children: tickets.asMap().entries.map((entry) {
                    final index = entry.key;
                    final ticket = entry.value;

                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                          bottom: index < tickets.length - 1 ? 16 : 0,
                        ),
                        child: TweenAnimationBuilder<double>(
                          duration:
                              Duration(milliseconds: 600 + (index * 200)),
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, value, child) {
                            return Transform.translate(
                              offset: Offset(50 * (1 - value), 0),
                              child: Opacity(
                                opacity: value,
                                child: _buildSecondaryCard(context, ticket),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildSecondaryCard(BuildContext context, Ticket ticket) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            colorScheme.surface,
            colorScheme.surfaceVariant.withOpacity(0.5),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Card(
        elevation: 0,
        color: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: CallCard(ticket: ticket, isSmall: true),
        ),
      ),
    );
  }

  Widget _buildEmptySecondary(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty_rounded,
              size: 32,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              'Sin turnos\npendientes',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter para crear un patrón geométrico sutil de fondo
class _GeometricPatternPainter extends CustomPainter {
  final Color color;

  _GeometricPatternPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const spacing = 100.0;

    // Grid diagonal sutil
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i - size.height, size.height),
        paint,
      );
    }

    // Líneas horizontales espaciadas
    for (double i = 0; i < size.height + spacing; i += spacing * 1.5) {
      canvas.drawLine(
        Offset(0, i),
        Offset(size.width, i),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Estados mejorados

/// Pantalla de carga profesional
class _LoadingScreen extends StatelessWidget {
  final Widget logo;

  const _LoadingScreen({required this.logo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withOpacity(0.1),
              colorScheme.surface,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo animado
              TweenAnimationBuilder<double>(
                duration: const Duration(seconds: 2),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: 0.8 + (0.2 * math.sin(value * math.pi * 2)),
                    child: Opacity(
                      opacity: 0.7 + (0.3 * math.sin(value * math.pi * 2)),
                      child: logo,
                    ),
                  );
                },
              ),

              const SizedBox(height: 48),

              // Indicador de carga personalizado
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Cargando turnos...',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Conectando con el sistema',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pantalla de error mejorada
class _ErrorScreen extends StatelessWidget {
  final String error;
  final Widget logo;
  final VoidCallback? onRetry;

  const _ErrorScreen({
    required this.error,
    required this.logo,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.errorContainer.withOpacity(0.1),
              colorScheme.surface,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo con opacidad reducida
                Opacity(opacity: 0.3, child: logo),

                const SizedBox(height: 48),

                // Icono de error
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Icon(
                    Icons.wifi_off_rounded,
                    size: 40,
                    color: colorScheme.onErrorContainer,
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  'Error de Conexión',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                Text(
                  'No se pudo conectar con el servidor',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 32),

                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pantalla vacía mejorada
class _EmptyScreen extends StatelessWidget {
  final Widget logo;

  const _EmptyScreen({required this.logo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withOpacity(0.05),
              colorScheme.surface,
              colorScheme.surfaceVariant.withOpacity(0.1),
            ],
            stops: const [0.0, 0.5, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo principal con animación suave
              TweenAnimationBuilder<double>(
                duration: const Duration(seconds: 3),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: 0.9 + (0.1 * math.sin(value * math.pi)),
                    child: Opacity(
                      opacity: 0.8 + (0.2 * math.sin(value * math.pi * 0.5)),
                      child: logo,
                    ),
                  );
                },
              ),

              const SizedBox(height: 48),

              // Mensaje principal
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.pending_actions_rounded,
                      size: 48,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Sistema Listo',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Esperando próximos turnos...',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Indicador de estado
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sistema Activo',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
