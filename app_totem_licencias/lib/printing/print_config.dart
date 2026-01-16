// lib/printing/print_config.dart
class PrintConfig {
  /// Nombre EXACTO de la cola en Windows (Panel de Control > Impresoras)
  static const String printerNameLicencias = 'REXOD RMP-8300';

  /// Impresora SOLO para examen práctico
  static const String printerNamePractico  = 'POS-80C'; // 👈 aquí

  /// Codepage ESC/POS:
  /// 16 = Windows-1252 (tildes/ñ) | 17/19 son alternativas si tu modelo no acepta 16
  static const int codepage = 16;

  /// Ruta del logo para imprimir en el ticket (PNG/JPG).
  /// Cambia si tu carpeta de assets es distinta.
static const String logoPath = r'C:\Insico\assets\logo.png';

  /// Ancho máximo del logo (px) — 58mm ≈ 384px, 80mm ≈ 576px.
  static const int logoMaxWidth = 384;

  /// Si algo sale raro con tildes en TU impresora, pon esto en true
  /// (fuerza textos fijos sin acentos). Normalmente debe quedar en false.
  static const bool asciiOnlyLabels = false;
}
