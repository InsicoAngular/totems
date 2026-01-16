

namespace FirmaIcerServices
{
    
    
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ServiceModel.ServiceContractAttribute(ConfigurationName="ServiceReference.FirmaElectronicaSoap")]
    public interface FirmaElectronicaSoap
    {
        
        [System.ServiceModel.OperationContractAttribute(Action="http://tempuri.org/FirmaDocumento", ReplyAction="*")]
        System.Threading.Tasks.Task<FirmaIcerServices.FirmaDocumentoResponse> FirmaDocumentoAsync(FirmaIcerServices.FirmaDocumentoRequest request);
        
        [System.ServiceModel.OperationContractAttribute(Action="http://tempuri.org/ConsultaDocumentoByGuid", ReplyAction="*")]
        System.Threading.Tasks.Task<FirmaIcerServices.ConsultaDocumentoByGuidResponse> ConsultaDocumentoByGuidAsync(FirmaIcerServices.ConsultaDocumentoByGuidRequest request);
        
        [System.ServiceModel.OperationContractAttribute(Action="http://tempuri.org/SolicitarGuid", ReplyAction="*")]
        System.Threading.Tasks.Task<FirmaIcerServices.SolicitarGuidResponse> SolicitarGuidAsync(FirmaIcerServices.SolicitarGuidRequest request);
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
    [System.ServiceModel.MessageContractAttribute(IsWrapped=false)]
    public partial class FirmaDocumentoRequest
    {
        
        [System.ServiceModel.MessageBodyMemberAttribute(Name="FirmaDocumento", Namespace="http://tempuri.org/", Order=0)]
        public FirmaIcerServices.FirmaDocumentoRequestBody Body;
        
        public FirmaDocumentoRequest()
        {
        }
        
        public FirmaDocumentoRequest(FirmaIcerServices.FirmaDocumentoRequestBody Body)
        {
            this.Body = Body;
        }
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
    [System.Runtime.Serialization.DataContractAttribute(Namespace="http://tempuri.org/")]
    public partial class FirmaDocumentoRequestBody
    {
        
        [System.Runtime.Serialization.DataMemberAttribute(EmitDefaultValue=false, Order=0)]
        public string Usuario;
        
        [System.Runtime.Serialization.DataMemberAttribute(EmitDefaultValue=false, Order=1)]
        public string Clave;
        
        [System.Runtime.Serialization.DataMemberAttribute(EmitDefaultValue=false, Order=2)]
        public string SobreXML;
        
        public FirmaDocumentoRequestBody()
        {
        }
        
        public FirmaDocumentoRequestBody(string Usuario, string Clave, string SobreXML)
        {
            this.Usuario = Usuario;
            this.Clave = Clave;
            this.SobreXML = SobreXML;
        }
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
    [System.ServiceModel.MessageContractAttribute(IsWrapped=false)]
    public partial class FirmaDocumentoResponse
    {
        
        [System.ServiceModel.MessageBodyMemberAttribute(Name="FirmaDocumentoResponse", Namespace="http://tempuri.org/", Order=0)]
        public FirmaIcerServices.FirmaDocumentoResponseBody Body;
        
        public FirmaDocumentoResponse()
        {
        }
        
        public FirmaDocumentoResponse(FirmaIcerServices.FirmaDocumentoResponseBody Body)
        {
            this.Body = Body;
        }
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
    [System.Runtime.Serialization.DataContractAttribute(Namespace="http://tempuri.org/")]
    public partial class FirmaDocumentoResponseBody
    {
        
        [System.Runtime.Serialization.DataMemberAttribute(EmitDefaultValue=false, Order=0)]
        public string FirmaDocumentoResult;
        
        public FirmaDocumentoResponseBody()
        {
        }
        
        public FirmaDocumentoResponseBody(string FirmaDocumentoResult)
        {
            this.FirmaDocumentoResult = FirmaDocumentoResult;
        }
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
    [System.ServiceModel.MessageContractAttribute(IsWrapped=false)]
    public partial class ConsultaDocumentoByGuidRequest
    {
        
        [System.ServiceModel.MessageBodyMemberAttribute(Name="ConsultaDocumentoByGuid", Namespace="http://tempuri.org/", Order=0)]
        public FirmaIcerServices.ConsultaDocumentoByGuidRequestBody Body;
        
        public ConsultaDocumentoByGuidRequest()
        {
        }
        
        public ConsultaDocumentoByGuidRequest(FirmaIcerServices.ConsultaDocumentoByGuidRequestBody Body)
        {
            this.Body = Body;
        }
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
    [System.Runtime.Serialization.DataContractAttribute(Namespace="http://tempuri.org/")]
    public partial class ConsultaDocumentoByGuidRequestBody
    {
        
        [System.Runtime.Serialization.DataMemberAttribute(EmitDefaultValue=false, Order=0)]
        public string Usuario;
        
        [System.Runtime.Serialization.DataMemberAttribute(EmitDefaultValue=false, Order=1)]
        public string Clave;
        
        [System.Runtime.Serialization.DataMemberAttribute(EmitDefaultValue=false, Order=2)]
        public string CodigoGuid;
        
        public ConsultaDocumentoByGuidRequestBody()
        {
        }
        
        public ConsultaDocumentoByGuidRequestBody(string Usuario, string Clave, string CodigoGuid)
        {
            this.Usuario = Usuario;
            this.Clave = Clave;
            this.CodigoGuid = CodigoGuid;
        }
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
    [System.ServiceModel.MessageContractAttribute(IsWrapped=false)]
    public partial class ConsultaDocumentoByGuidResponse
    {
        
        [System.ServiceModel.MessageBodyMemberAttribute(Name="ConsultaDocumentoByGuidResponse", Namespace="http://tempuri.org/", Order=0)]
        public FirmaIcerServices.ConsultaDocumentoByGuidResponseBody Body;
        
        public ConsultaDocumentoByGuidResponse()
        {
        }
        
        public ConsultaDocumentoByGuidResponse(FirmaIcerServices.ConsultaDocumentoByGuidResponseBody Body)
        {
            this.Body = Body;
        }
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
    [System.Runtime.Serialization.DataContractAttribute(Namespace="http://tempuri.org/")]
    public partial class ConsultaDocumentoByGuidResponseBody
    {
        
        [System.Runtime.Serialization.DataMemberAttribute(EmitDefaultValue=false, Order=0)]
        public string ConsultaDocumentoByGuidResult;
        
        public ConsultaDocumentoByGuidResponseBody()
        {
        }
        
        public ConsultaDocumentoByGuidResponseBody(string ConsultaDocumentoByGuidResult)
        {
            this.ConsultaDocumentoByGuidResult = ConsultaDocumentoByGuidResult;
        }
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
    [System.ServiceModel.MessageContractAttribute(IsWrapped=false)]
    public partial class SolicitarGuidRequest
    {
        
        [System.ServiceModel.MessageBodyMemberAttribute(Name="SolicitarGuid", Namespace="http://tempuri.org/", Order=0)]
        public FirmaIcerServices.SolicitarGuidRequestBody Body;
        
        public SolicitarGuidRequest()
        {
        }
        
        public SolicitarGuidRequest(FirmaIcerServices.SolicitarGuidRequestBody Body)
        {
            this.Body = Body;
        }
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
    [System.Runtime.Serialization.DataContractAttribute(Namespace="http://tempuri.org/")]
    public partial class SolicitarGuidRequestBody
    {
        
        [System.Runtime.Serialization.DataMemberAttribute(EmitDefaultValue=false, Order=0)]
        public string Usuario;
        
        [System.Runtime.Serialization.DataMemberAttribute(EmitDefaultValue=false, Order=1)]
        public string Clave;
        
        public SolicitarGuidRequestBody()
        {
        }
        
        public SolicitarGuidRequestBody(string Usuario, string Clave)
        {
            this.Usuario = Usuario;
            this.Clave = Clave;
        }
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
    [System.ServiceModel.MessageContractAttribute(IsWrapped=false)]
    public partial class SolicitarGuidResponse
    {
        
        [System.ServiceModel.MessageBodyMemberAttribute(Name="SolicitarGuidResponse", Namespace="http://tempuri.org/", Order=0)]
        public FirmaIcerServices.SolicitarGuidResponseBody Body;
        
        public SolicitarGuidResponse()
        {
        }
        
        public SolicitarGuidResponse(FirmaIcerServices.SolicitarGuidResponseBody Body)
        {
            this.Body = Body;
        }
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
    [System.Runtime.Serialization.DataContractAttribute(Namespace="http://tempuri.org/")]
    public partial class SolicitarGuidResponseBody
    {
        
        [System.Runtime.Serialization.DataMemberAttribute(EmitDefaultValue=false, Order=0)]
        public string SolicitarGuidResult;
        
        public SolicitarGuidResponseBody()
        {
        }
        
        public SolicitarGuidResponseBody(string SolicitarGuidResult)
        {
            this.SolicitarGuidResult = SolicitarGuidResult;
        }
    }
    
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    public interface FirmaElectronicaSoapChannel : FirmaIcerServices.FirmaElectronicaSoap, System.ServiceModel.IClientChannel
    {
    }
    
    [System.Diagnostics.DebuggerStepThroughAttribute()]
    [System.CodeDom.Compiler.GeneratedCodeAttribute("Microsoft.Tools.ServiceModel.Svcutil", "2.1.0")]
    public partial class FirmaElectronicaSoapClient : System.ServiceModel.ClientBase<FirmaIcerServices.FirmaElectronicaSoap>, FirmaIcerServices.FirmaElectronicaSoap
    {
        
        /// <summary>
        /// Implemente este método parcial para configurar el punto de conexión de servicio.
        /// </summary>
        /// <param name="serviceEndpoint">El punto de conexión para configurar</param>
        /// <param name="clientCredentials">Credenciales de cliente</param>
        static partial void ConfigureEndpoint(System.ServiceModel.Description.ServiceEndpoint serviceEndpoint, System.ServiceModel.Description.ClientCredentials clientCredentials);
        
        public FirmaElectronicaSoapClient(EndpointConfiguration endpointConfiguration) : 
                base(FirmaElectronicaSoapClient.GetBindingForEndpoint(endpointConfiguration), FirmaElectronicaSoapClient.GetEndpointAddress(endpointConfiguration))
        {
            this.Endpoint.Name = endpointConfiguration.ToString();
            ConfigureEndpoint(this.Endpoint, this.ClientCredentials);
        }
        
        public FirmaElectronicaSoapClient(EndpointConfiguration endpointConfiguration, string remoteAddress) : 
                base(FirmaElectronicaSoapClient.GetBindingForEndpoint(endpointConfiguration), new System.ServiceModel.EndpointAddress(remoteAddress))
        {
            this.Endpoint.Name = endpointConfiguration.ToString();
            ConfigureEndpoint(this.Endpoint, this.ClientCredentials);
        }
        
        public FirmaElectronicaSoapClient(EndpointConfiguration endpointConfiguration, System.ServiceModel.EndpointAddress remoteAddress) : 
                base(FirmaElectronicaSoapClient.GetBindingForEndpoint(endpointConfiguration), remoteAddress)
        {
            this.Endpoint.Name = endpointConfiguration.ToString();
            ConfigureEndpoint(this.Endpoint, this.ClientCredentials);
        }
        
        public FirmaElectronicaSoapClient(System.ServiceModel.Channels.Binding binding, System.ServiceModel.EndpointAddress remoteAddress) : 
                base(binding, remoteAddress)
        {
        }
        
        [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
        System.Threading.Tasks.Task<FirmaIcerServices.FirmaDocumentoResponse> FirmaIcerServices.FirmaElectronicaSoap.FirmaDocumentoAsync(FirmaIcerServices.FirmaDocumentoRequest request)
        {
            return base.Channel.FirmaDocumentoAsync(request);
        }
        
        public System.Threading.Tasks.Task<FirmaIcerServices.FirmaDocumentoResponse> FirmaDocumentoAsync(string Usuario, string Clave, string SobreXML)
        {
            FirmaIcerServices.FirmaDocumentoRequest inValue = new FirmaIcerServices.FirmaDocumentoRequest();
            inValue.Body = new FirmaIcerServices.FirmaDocumentoRequestBody();
            inValue.Body.Usuario = Usuario;
            inValue.Body.Clave = Clave;
            inValue.Body.SobreXML = SobreXML;
            return ((FirmaIcerServices.FirmaElectronicaSoap)(this)).FirmaDocumentoAsync(inValue);
        }
        
        [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
        System.Threading.Tasks.Task<FirmaIcerServices.ConsultaDocumentoByGuidResponse> FirmaIcerServices.FirmaElectronicaSoap.ConsultaDocumentoByGuidAsync(FirmaIcerServices.ConsultaDocumentoByGuidRequest request)
        {
            return base.Channel.ConsultaDocumentoByGuidAsync(request);
        }
        
        public System.Threading.Tasks.Task<FirmaIcerServices.ConsultaDocumentoByGuidResponse> ConsultaDocumentoByGuidAsync(string Usuario, string Clave, string CodigoGuid)
        {
            FirmaIcerServices.ConsultaDocumentoByGuidRequest inValue = new FirmaIcerServices.ConsultaDocumentoByGuidRequest();
            inValue.Body = new FirmaIcerServices.ConsultaDocumentoByGuidRequestBody();
            inValue.Body.Usuario = Usuario;
            inValue.Body.Clave = Clave;
            inValue.Body.CodigoGuid = CodigoGuid;
            return ((FirmaIcerServices.FirmaElectronicaSoap)(this)).ConsultaDocumentoByGuidAsync(inValue);
        }
        
        [System.ComponentModel.EditorBrowsableAttribute(System.ComponentModel.EditorBrowsableState.Advanced)]
        System.Threading.Tasks.Task<FirmaIcerServices.SolicitarGuidResponse> FirmaIcerServices.FirmaElectronicaSoap.SolicitarGuidAsync(FirmaIcerServices.SolicitarGuidRequest request)
        {
            return base.Channel.SolicitarGuidAsync(request);
        }
        
        public System.Threading.Tasks.Task<FirmaIcerServices.SolicitarGuidResponse> SolicitarGuidAsync(string Usuario, string Clave)
        {
            FirmaIcerServices.SolicitarGuidRequest inValue = new FirmaIcerServices.SolicitarGuidRequest();
            inValue.Body = new FirmaIcerServices.SolicitarGuidRequestBody();
            inValue.Body.Usuario = Usuario;
            inValue.Body.Clave = Clave;
            return ((FirmaIcerServices.FirmaElectronicaSoap)(this)).SolicitarGuidAsync(inValue);
        }
        
        public virtual System.Threading.Tasks.Task OpenAsync()
        {
            return System.Threading.Tasks.Task.Factory.FromAsync(((System.ServiceModel.ICommunicationObject)(this)).BeginOpen(null, null), new System.Action<System.IAsyncResult>(((System.ServiceModel.ICommunicationObject)(this)).EndOpen));
        }
        
        private static System.ServiceModel.Channels.Binding GetBindingForEndpoint(EndpointConfiguration endpointConfiguration)
        {
            if ((endpointConfiguration == EndpointConfiguration.FirmaElectronicaSoap))
            {
                System.ServiceModel.BasicHttpBinding result = new System.ServiceModel.BasicHttpBinding();
                result.MaxBufferSize = int.MaxValue;
                result.ReaderQuotas = System.Xml.XmlDictionaryReaderQuotas.Max;
                result.MaxReceivedMessageSize = int.MaxValue;
                result.AllowCookies = true;
                result.Security.Mode = System.ServiceModel.BasicHttpSecurityMode.Transport;
                return result;
            }
            if ((endpointConfiguration == EndpointConfiguration.FirmaElectronicaSoap12))
            {
                System.ServiceModel.Channels.CustomBinding result = new System.ServiceModel.Channels.CustomBinding();
                System.ServiceModel.Channels.TextMessageEncodingBindingElement textBindingElement = new System.ServiceModel.Channels.TextMessageEncodingBindingElement();
                textBindingElement.MessageVersion = System.ServiceModel.Channels.MessageVersion.CreateVersion(System.ServiceModel.EnvelopeVersion.Soap12, System.ServiceModel.Channels.AddressingVersion.None);
                result.Elements.Add(textBindingElement);
                System.ServiceModel.Channels.HttpsTransportBindingElement httpsBindingElement = new System.ServiceModel.Channels.HttpsTransportBindingElement();
                httpsBindingElement.AllowCookies = true;
                httpsBindingElement.MaxBufferSize = int.MaxValue;
                httpsBindingElement.MaxReceivedMessageSize = int.MaxValue;
                result.Elements.Add(httpsBindingElement);
                return result;
            }
            throw new System.InvalidOperationException(string.Format("No se pudo encontrar un punto de conexión con el nombre \"{0}\".", endpointConfiguration));
        }
        
        private static System.ServiceModel.EndpointAddress GetEndpointAddress(EndpointConfiguration endpointConfiguration)
        {
            if ((endpointConfiguration == EndpointConfiguration.FirmaElectronicaSoap))
            {
                return new System.ServiceModel.EndpointAddress("https://plataformafirma.ecertchile.cl/WebService/FirmaElectronica.asmx");
            }
            if ((endpointConfiguration == EndpointConfiguration.FirmaElectronicaSoap12))
            {
                return new System.ServiceModel.EndpointAddress("https://plataformafirma.ecertchile.cl/WebService/FirmaElectronica.asmx");
            }
            throw new System.InvalidOperationException(string.Format("No se pudo encontrar un punto de conexión con el nombre \"{0}\".", endpointConfiguration));
        }
        
        public enum EndpointConfiguration
        {
            
            FirmaElectronicaSoap,
            
            FirmaElectronicaSoap12,
        }
    }
}
