namespace tbk_pos.infractructure.dto
{
    public class InitFoliosResponseDto
    {
        public bool success { get; set; }
        public string message { get; set; }
        public List<dynamic> init_folios { get; set; }
    }
}
