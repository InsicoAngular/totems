using Transbank.Responses.CommonResponses;

namespace tbk_pos.infractructure.dto
{
    public class KeyResponseDto
    {
        public bool success { get; set; }
        public string message { get; set; }
        public LoadKeysResponse? data { get; set; }
    }
}
