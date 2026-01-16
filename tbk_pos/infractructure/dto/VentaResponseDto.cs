using Transbank.Responses.AutoservicioResponse;

namespace tbk_pos.infractructure.dto
{
    public class VentaResponseDto
    {
        public bool success { get; set; }
        public string message { get; set; }
        public SaleResponse? data { get; set; }



    }
}
