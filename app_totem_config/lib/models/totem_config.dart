// lib/models/totem_config.dart

import 'package:flutter/material.dart';

class TotemConfig {
  final String welcomeText;
  final String hashtag;
  final String marqueeText;
  final int    buttonBg;
  final int    buttonText;
  final String assetsDir;
  final int    waitingLayout;
  final bool   isWaitingScreen;

  TotemConfig({
    required this.welcomeText,
    required this.hashtag,
    required this.marqueeText,
    required this.buttonBg,
    required this.buttonText,
    required this.assetsDir,
    required this.waitingLayout,
    this.isWaitingScreen = false,
  });

  Map<String, dynamic> toMap() => {
        'welcomeText':     welcomeText,
        'hashtag':         hashtag,
        'marqueeText':     marqueeText,
        'buttonBg':        buttonBg,
        'buttonText':      buttonText,
        'assetsDir':       assetsDir,
        'waitingLayout':   waitingLayout,
        'isWaitingScreen': isWaitingScreen,
      };

  factory TotemConfig.fromMap(Map<String, dynamic> m) => TotemConfig(
        welcomeText:     m['welcomeText']     as String? ?? '',
        hashtag:         m['hashtag']         as String? ?? '',
        marqueeText:     m['marqueeText']     as String? ?? '',
        buttonBg:        m['buttonBg']        as int?    ?? Colors.deepPurple.value,
        buttonText:      m['buttonText']      as int?    ?? Colors.white.value,
        assetsDir:       m['assetsDir']       as String? ?? '',
        waitingLayout:   m['waitingLayout']   as int?    ?? 1,
        isWaitingScreen: (m['isWaitingScreen'] as bool?) ?? false,
      );
}
