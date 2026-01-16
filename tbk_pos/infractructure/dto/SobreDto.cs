namespace tbk_pos.infractructure.dto
{
    using System.Xml.Serialization;

    [XmlRoot("Sobre")]
    public class Sobre
    {
        [XmlElement("Cabecera")]
        public Cabecera Cabecera { get; set; }
    }

    public class Cabecera
    {
        [XmlElement("Resultado")]
        public Resultado Resultado { get; set; }
    }

    public class Resultado
    {
        [XmlElement("Estado")]
        public bool Estado { get; set; }

        [XmlElement("Codigo")]
        public int Codigo { get; set; }

        [XmlElement("Descripcion")]
        public string Descripcion { get; set; }

        [XmlElement("Detalle")]
        public string Detalle { get; set; }

        [XmlElement("Url")]
        public string Url { get; set; }

        [XmlElement("Guid")]
        public string Guid { get; set; }
    }

}
