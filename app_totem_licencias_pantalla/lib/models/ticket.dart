class Ticket {
  final int id;
  final String name;
  final String station;   // ✅ nombre de la estación (antes "module")
  final bool isManual;
  final String tipoEspera;

  const Ticket({
    required this.id,
    required this.name,
    required this.station,
    this.isManual = false,
    this.tipoEspera = '',
  });

  // —— Alias de compatibilidad (no romper código viejo) ——
  String get module => station;

  // Etiqueta legible para el área/tipo
  String get areaLabel {
    switch (tipoEspera.toUpperCase()) {
      case 'M': return 'Médico';
      case 'P': return 'Psicométrico';
      case 'S': return 'Social';
      case 'U': return 'Universal';
      default:  return 'General';
    }
  }

  // ---- JSON helpers ----
  factory Ticket.fromJson(Map<String, dynamic> json) {
    T pick<T>(List<String> keys, {T? orElse}) {
      for (final k in keys) {
        if (json.containsKey(k) && json[k] != null) {
          final v = json[k];
          if (T == bool) {
            if (v is bool) return v as T;
            if (v is num)  return (v != 0) as T;
            if (v is String) return (v == '1' || v.toLowerCase() == 'true') as T;
          }
          return v as T;
        }
      }
      return orElse as T;
    }

    final int id = int.tryParse(
      (pick(['id','Id','ID','id_llamados','id_llamado'], orElse: '0')).toString(),
    ) ?? 0;

    final String name = (pick<String>(['name','nombre','NombreCompleto'], orElse: '')).toString();

    // ✅ Acepta cualquiera de estos nombres que puede mandar el backend
    final String station = (pick([
      'station','estacion','Nombre_Estacion','nombre_estacion',
      'module','modulo', // compatibilidad si aún viene "módulo"
    ], orElse: '')).toString();

    final bool isManual = pick<bool>(['isManual','EsManual'], orElse: false);

    final String tipoEspera = (pick<String>(['tipoEspera','tipo_espera'], orElse: '')).toString();

    return Ticket(
      id: id,
      name: name,
      station: station,
      isManual: isManual,
      tipoEspera: tipoEspera,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'station': station,
    'module': station, // 👈 alias por si algo externo aún espera "module"
    'isManual': isManual,
    'tipoEspera': tipoEspera,
  };

  Ticket copyWith({
    int? id,
    String? name,
    String? station,
    String? module, // 👈 alias (si te pasan module, lo tomamos como station)
    bool? isManual,
    String? tipoEspera,
  }) => Ticket(
    id: id ?? this.id,
    name: name ?? this.name,
    station: station ?? module ?? this.station,
    isManual: isManual ?? this.isManual,
    tipoEspera: tipoEspera ?? this.tipoEspera,
  );
}
