import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:app_totem_licencias/config/database_config.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_header.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  late final PageController _page;
  List<File> _slides = [];
  int _cur = 0;
  Timer? _timer;

  Color _buttonBg = Colors.deepPurple;
  Color _buttonFg = Colors.white;
  Color _surfaceBg = const Color(0xFFF5F7FB);
  String _welcome = 'Bienvenido a la plataforma de Autoservicios';

  @override
  void initState() {
    super.initState();
    _page = PageController();
    _loadPrefsAndImages();
  }

  Future<void> _loadPrefsAndImages() async {
    final pfs = await SharedPreferences.getInstance();

    setState(() {
      _buttonBg = Color(pfs.getInt('buttonBg') ?? Colors.deepPurple.value);
      _buttonFg = Color(pfs.getInt('buttonText') ?? Colors.white.value);
      _welcome = pfs.getString('welcomeText') ?? _welcome;
      _surfaceBg = Color(
        pfs.getInt('bgSurface') ?? const Color(0xFFF5F7FB).value,
      );
    });

    final dir = pfs.getString('assetsDir') ?? r'C:\Insico\assets\';
    final files = [
      File(p.join(dir, '1.jpg')),
      File(p.join(dir, '2.jpg')),
      File(p.join(dir, '3.jpg')),
    ];
    _slides = files.where((f) => f.existsSync()).toList();
    if (_slides.isEmpty) _slides.add(File(p.join(dir, 'logo.png')));
    _startCarousel();
  }

  void _startCarousel() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _slides.isEmpty) return;
      setState(() => _cur = (_cur + 1) % _slides.length);
      if (_page.hasClients) {
        _page.animateToPage(
          _cur,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  @override
  Widget build(BuildContext context) {
    if (_slides.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isPortrait = size.height >= size.width;

    final baseW = size.width;
    final baseH = size.height;
    final pad = _clamp(baseW * 0.022, 16, 28);
    final radius = _clamp(baseW * 0.028, 18, 32);
    final heroHeight = _clamp(baseH * (isPortrait ? 0.56 : 0.45), 480, 1000);
    final titleSize = _clamp(baseW * 0.046, 24, 50);
    final buttonHeight = _clamp(baseH * 0.095, 80, 132);
    final indicatorSize = _clamp(baseW * 0.016, 12, 20);

    final isPractico = DatabaseConfig.practico;
    const noKiosk = bool.fromEnvironment('NO_KIOSK', defaultValue: false);

    Widget buildContent({required bool boundedHeight}) {
      return Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(
            tickerHeight: 72,
            brandHeight: 170,
            logoMaxHeight: 140,
            hashtagFontSize: 20,
            marqueeFontSize: 20,
          ),
          SizedBox(height: _clamp(baseH * 0.012, 8, 24)),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Card(
                elevation: 8,
                color: Colors.white,
                shadowColor: Colors.black.withOpacity(0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: heroHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        controller: _page,
                        itemCount: _slides.length,
                        itemBuilder:
                            (_, i) => Image.file(_slides[i], fit: BoxFit.cover),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.12),
                                Colors.transparent,
                                Colors.black.withOpacity(0.18),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 14,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _slides.length,
                            (index) => AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: EdgeInsets.symmetric(
                                horizontal: indicatorSize * 0.3,
                              ),
                              width:
                                  _cur == index
                                      ? indicatorSize * 2.2
                                      : indicatorSize,
                              height: indicatorSize * 0.6,
                              decoration: BoxDecoration(
                                color:
                                    _cur == index
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.45),
                                borderRadius: BorderRadius.circular(
                                  indicatorSize,
                                ),
                                boxShadow:
                                    _cur == index
                                        ? [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.22,
                                            ),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ]
                                        : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: _clamp(baseH * 0.02, 16, 32)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Text(
              _welcome,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: titleSize,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                height: 1.15,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.07),
                    offset: const Offset(0, 1),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
          if (boundedHeight)
            const Spacer()
          else
            SizedBox(height: _clamp(baseH * 0.03, 20, 40)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: SizedBox(
              width: double.infinity,
              height: buttonHeight,
              child: ElevatedButton(
                onPressed: () {
                  if (isPractico && noKiosk) {
                    Navigator.pushNamed(context, '/practico-ops');
                  } else if (isPractico) {
                    Navigator.pushNamed(
                      context,
                      '/pad',
                      arguments: {'flow': 'practico'},
                    );
                  } else {
                    Navigator.pushNamed(context, '/tramites');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _buttonBg,
                  foregroundColor: _buttonFg,
                  elevation: 12,
                  shadowColor: Colors.black.withOpacity(0.28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app, size: _clamp(baseW * 0.06, 34, 48)),
                    SizedBox(width: _clamp(baseW * 0.014, 10, 22)),
                    Text(
                      'INICIAR',
                      style: TextStyle(
                        fontSize: _clamp(baseW * 0.06, 28, 54),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height:
                MediaQuery.of(context).padding.bottom +
                _clamp(baseH * 0.02, 12, 30),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: _surfaceBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tallEnough = constraints.maxHeight >= 900;
            if (tallEnough) {
              return SizedBox(
                width: double.infinity,
                height: constraints.maxHeight,
                child: buildContent(boundedHeight: true),
              );
            }
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: buildContent(boundedHeight: false),
              ),
            );
          },
        ),
      ),
    );
  }
}
