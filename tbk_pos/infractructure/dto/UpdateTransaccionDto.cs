namespace tbk_pos.infractructure.dto
{
    public class UpdateTransaccionDto
    {
        public string CodeStatus { get; set; }
        public string Terminal { get; set; }
        public string Fecha { get; set; } // Asegúrate de que el formato sea compatible con tu base de datos
        public string Hora { get; set; }  // Asegúrate de que el formato sea compatible con tu base de datos
        public string Tarjeta { get; set; }
        public int Cuenta { get; set; }
        public string Marca { get; set; }
        public string Autorizacion { get; set; }
        public string Operacion { get; set; }
    }
}
