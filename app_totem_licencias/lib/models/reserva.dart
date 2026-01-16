class Reserva {
  final String numRut;
  final int correlativo;
  final String nombres;
  final String apellidos;
  final String fechaIngreso;
  final String fechaCitacion;
  final String horaCitacion;
  final String fechaPago;
  final int?  nComprobante;
  final String clase1;
  final String clase2;
  final String clase3;
  final String clase4;
  final String clase5;
  final String clase6;
  final String valorTramite;
  final String valorAntec;
  final String valorFoto;
  final String estado;
  final String folioF8;
  final String numSol;

  Reserva({
    required this.numRut,
    required this.correlativo,
    required this.nombres,
    required this.apellidos,
    required this.fechaIngreso,
    required this.fechaCitacion,
    required this.horaCitacion,
    required this.fechaPago,
    required this.nComprobante,
    required this.clase1,
    required this.clase2,
    required this.clase3,
    required this.clase4,
    required this.clase5,
    required this.clase6,
    required this.valorTramite,
    required this.valorAntec,
    required this.valorFoto,
    required this.estado,
    required this.folioF8,
    required this.numSol,
  });

  factory Reserva.fromJson(Map<String, dynamic> j) => Reserva(
        numRut:        j['L94_NUMRUT']        ?? '',
        correlativo:   j['L94_CORRELATIVO']   ?? 0,
        nombres:       j['L94_NOMBRES']       ?? '',
        apellidos:     j['L94_APELLIDOS']     ?? '',
        fechaIngreso:  j['L94_FECHAINGRESO']  ?? '',
        fechaCitacion: j['L94_FECHACITACION'] ?? '',
        horaCitacion:  j['L94_HORACITACION']  ?? '',
        fechaPago:     j['L94_FECHAPAGO']     ?? '',
        nComprobante:  j['L94_NCOMPROBANTE'],
        clase1:        j['L94_CLASE1']        ?? '',
        clase2:        j['L94_CLASE2']        ?? '',
        clase3:        j['L94_CLASE3']        ?? '',
        clase4:        j['L94_CLASE4']        ?? '',
        clase5:        j['L94_CLASE5']        ?? '',
        clase6:        j['L94_CLASE6']        ?? '',
        valorTramite:  j['L94_VALORTRAMITE']  ?.toString() ?? '',
        valorAntec:    j['L94_VALORANTEC']    ?.toString() ?? '',
        valorFoto:     j['L94_VALORFOTO']     ?.toString() ?? '',
        estado:        j['L94_ESTADO']        ?? '',
        folioF8:       j['L94_FOLIOF8']       ?? '',
        numSol:        j['L94_NUMSOL']        ?? '',
      );
}
