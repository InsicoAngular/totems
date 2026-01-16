class PracticoResult {
  final int personaId;
  final int rutNumero;
  final String rutDigito;
  final String nombre;
  final DateTime fechaResultado;
  final int etapaId;
  final int estadoId;
  final String resultado;

  PracticoResult({
    required this.personaId,
    required this.rutNumero,
    required this.rutDigito,
    required this.nombre,
    required this.fechaResultado,
    required this.etapaId,
    required this.estadoId,
    required this.resultado,
  });

  factory PracticoResult.fromJson(Map<String, dynamic> j) => PracticoResult(
        personaId     : j['PAPersonaId']                as int,
        rutNumero     : j['RutNumero']                  as int,
        rutDigito     : j['RutDigito'].toString(),
        nombre        : j['nombre']                     as String,
        fechaResultado: DateTime.parse(j['FechaResultado']),
        etapaId       : j['ALCParametro_General_Etapa_id'] as int,
        estadoId      : j['ALCEstado_id']               as int,
        resultado     : j['Resultado'].toString(),
      );
}
