import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/tts_service.dart';

final ttsProvider = Provider<TtsService>((ref) {
  final tts = TtsService();
  tts.init(); // fire & forget
  ref.onDispose(() => tts.dispose());
  return tts;
});
