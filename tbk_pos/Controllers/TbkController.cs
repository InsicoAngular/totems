using QRCoder;
using Microsoft.AspNetCore.Mvc;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Transbank.POSAutoservicio;
using Transbank.Responses.CommonResponses;
using Transbank.Responses.AutoservicioResponse;
using tbk_pos.infractructure.dto;
using ESC_POS_USB_NET.Printer;
using tbk_pos.infractructure.repository;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;
using QuestPDF.Fluent;
using FirmaIcerServices;
using System.Xml.Linq;
using System.ServiceModel;
using System.Net.Http;

namespace tbk_pos.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class TbkController : ControllerBase
    {
        private readonly string _portName;
        private readonly string _printerName;
        private readonly string _printerName2;
        private readonly string _fileExecutable;
        private readonly string _codigoBin;
        private readonly List<WebSocket> _webSocketClients;
        private readonly dbTbk _dbTbk;
        private readonly FirmaElectronicaSoapClient _client;

        // TbkController.cs  (campos privados)
        private readonly int _cajaIdBD;     // 102, para consultas
        private readonly string _numeroCaja;// 51, para imprimir en PDF


        private readonly string _usuario;
        private readonly string _clave;
        private readonly string _rutFirma;

        public TbkController(List<WebSocket> webSocketClients, dbTbk dbTbk, IConfiguration configuration, FirmaElectronicaSoapClient client)
        {
            _webSocketClients = webSocketClients;
            _dbTbk = dbTbk;
            _portName = configuration.GetValue<string>("Aplicacion:portName");
            _printerName = configuration.GetValue<string>("Aplicacion:printerName");
            _printerName2 = configuration.GetValue<string>("Aplicacion:printerName2");
            _fileExecutable = configuration.GetValue<string>("Aplicacion:fileExecutable");
            _cajaIdBD = configuration.GetValue<int>("Aplicacion:cajaId");
            _numeroCaja = configuration.GetValue<string>("Aplicacion:caja"); 
            _client = client;
            QuestPDF.Settings.License = LicenseType.Community;

            _usuario = configuration.GetValue<string>("FirmaElectronicaService:usuario");
            _clave = configuration.GetValue<string>("FirmaElectronicaService:pwd");
            _rutFirma = configuration.GetValue<string>("FirmaElectronicaService:rutfirma");
            _codigoBin = configuration.GetValue<string>("FirmaElectronicaService:codigoBin");
        }

        #region "Controllers"

        [HttpGet("getPorts")]
        public List<string> GetPorts()
        {
            return POSAutoservicio.Instance.ListPorts();
        }

        [HttpGet("poll")]
        public bool Poll()
        {
            try
            {
                POSAutoservicio.Instance.OpenPort(_portName);
                Task<bool> connected = POSAutoservicio.Instance.Poll();
                return connected?.Result ?? false;
            }
            catch
            {
                return false;
            }
            finally
            {
                if (POSAutoservicio.Instance.IsPortOpen)
                {
                    POSAutoservicio.Instance.ClosePort();
                }
            }
        }

        [HttpGet("loadKeys")]
        public KeyResponseDto LoadKeys()
        {
            try
            {
                POSAutoservicio.Instance.OpenPort(_portName);
                Task<LoadKeysResponse> response = POSAutoservicio.Instance.LoadKeys();
                return new KeyResponseDto
                {
                    success = true,
                    message = "Ejecución exitosa",
                    data = response.Result
                };
            }
            catch (Exception e)
            {
                while (e.InnerException != null)
                    e = e.InnerException;
                return new KeyResponseDto
                {
                    success = false,
                    message = e.Message,
                    data = null
                };
            }
            finally
            {
                if (POSAutoservicio.Instance.IsPortOpen)
                {
                    POSAutoservicio.Instance.ClosePort();
                }
            }
        }

        [HttpGet("closeDay")]
        public KeyResponseDto CloseDay()
        {
            try
            {
                POSAutoservicio.Instance.OpenPort(_portName);
                Task<CloseResponse> response = POSAutoservicio.Instance.Close(true);

                var dataresponse = response.Result;

                PrinCierre(dataresponse);

                return new KeyResponseDto
                {
                    success = true,
                    message = "Ejecución exitosa",
                    data = response.Result
                };
            }
            catch (Exception e)
            {
                while (e.InnerException != null)
                    e = e.InnerException;
                return new KeyResponseDto
                {
                    success = false,
                    message = e.Message,
                    data = null
                };
            }
            finally
            {
                if (POSAutoservicio.Instance.IsPortOpen)
                {
                    POSAutoservicio.Instance.ClosePort();
                }
            }
        }

        [HttpPost("sale")]
        public async Task<VentaResponseDto> Sale([FromBody] VentaRequestDto request)
        {
            // Log inicial
            await _dbTbk.InsertLogAsync(
                request.Folio.ToString(),
                $"[SALE] Iniciando venta. Monto={request.Monto}, Folio(s)={request.Folio}"
            );

            try
            {
                // Abrir el puerto
                if (!await TryOpenPortAsync(_portName, request.Folio.ToString()))
                {
                    await _dbTbk.InsertLogAsync(request.Folio.ToString(), $"[SALE] No se pudo abrir el puerto {_portName} tras varios intentos.");
                    return new VentaResponseDto
                    {
                        success = false,
                        message = $"Error: No se pudo abrir el puerto {_portName}. Por favor, inténtelo de nuevo.",
                        data = null
                    };
                }

                // pones el Poll:
                bool isReady = await POSAutoservicio.Instance.Poll();
                if (!isReady)
                {
                    await _dbTbk.InsertLogAsync(request.Folio.ToString(),
                        "[SALE] Poll fallido, terminal no responde.");
                    // cerrar puerto antes de salir
                    POSAutoservicio.Instance.ClosePort();
                    return new VentaResponseDto
                    {
                        success = false,
                        message = "Terminal no responde (Poll). Intenta de nuevo.",
                        data = null
                    };
                }

                // Suscribirse a mensajes intermedios
                POSAutoservicio.Instance.IntermediateResponseChange += NewIntermediateMessageReceived;

                // Ejecutar la venta
                SaleResponse saleResponse = await POSAutoservicio.Instance.Sale(
                    request.Monto,
                    request.Folio.ToString(),
                    true,  // Enviar mensajes intermedios
                    true   // Etc.
                );

                // Log: respuesta recibida del POS
                await _dbTbk.InsertLogAsync(
                    request.Folio.ToString(),
                    $"[SALE] Respuesta POS: Code={saleResponse.ResponseCode}, " +
                    $"Authorization={saleResponse.AuthorizationCode}, " +
                    $"Operation={saleResponse.OperationNumber}"
                );

                // Si ResponseCode = 0 => Aprobada
                if (saleResponse.ResponseCode == 0)
                {
                    await _dbTbk.InsertLogAsync(
                        request.Folio.ToString(),
                        "[SALE] Transacción aprobada (ACK)"
                    );

                    // Actualizar la BD y/o imprimir:
                    await ActualizaPago(request.Folio, saleResponse);

                    // Devolver al frontend EXACTO lo que dice el POS
                    var linesFromPos = saleResponse.PrintingField != null
                        ? string.Join("\n", saleResponse.PrintingField)
                        : "(Sin texto desde el POS)";

                    return new VentaResponseDto
                    {
                        success = true,
                        message = linesFromPos,
                        data = saleResponse
                    };
                }
                else
                {
                    // Rechazada
                    await _dbTbk.InsertLogAsync(
                        request.Folio.ToString(),
                        $"[SALE] Transacción rechazada (NAK) - Código: {saleResponse.ResponseCode}"
                    );

                    // Igual puedes formar un "mensaje POS" si quieres
                    var linesFromPos = saleResponse.PrintingField != null
                        ? string.Join("\n", saleResponse.PrintingField)
                        : "(Sin texto desde el POS)";

                    return new VentaResponseDto
                    {
                        success = false,
                        // Algo como: "RECHAZADA - 99 - Mensaje POS..."
                        message = $"RECHAZADA - Código {saleResponse.ResponseCode}:\n{linesFromPos}",
                        data = saleResponse
                    };
                }
            }
            catch (Exception e)
            {
                // Manejo de la excepción
                var originalEx = e;
                var sb = new StringBuilder();
                sb.AppendLine("[SALE][ERROR] Excepción detectada:");
                while (originalEx != null)
                {
                    sb.AppendLine($"Message: {originalEx.Message}");
                    sb.AppendLine($"StackTrace: {originalEx.StackTrace}");
                    originalEx = originalEx.InnerException;
                }

                // Guardar en log
                await _dbTbk.InsertLogAsync(request.Folio.ToString(), sb.ToString());

                // Retornar error genérico
                return new VentaResponseDto
                {
                    success = false,
                    message = e.Message,
                    data = null
                };
            }
            finally
            {
                // 6) Cerrar puerto + delay + limpieza de eventos
                if (POSAutoservicio.Instance.IsPortOpen)
                {
                    POSAutoservicio.Instance.ClosePort();
                    await _dbTbk.InsertLogAsync(
                        request.Folio.ToString(),
                        $"[SALE] Puerto {_portName} cerrado"
                    );
                    await Task.Delay(500);
                }
                POSAutoservicio.Instance.IntermediateResponseChange -= NewIntermediateMessageReceived;
            }
        }

        [HttpGet("printertoner/{folio}")]
        public async Task<IActionResult> Printertoner(int folio)
        {
            try
            {
                // Obtener detalle de pago
                var datalle = await _dbTbk.GetDetallePago(folio);

                // Convertir a lista
                var lstdetalle = datalle.ToList();

                // Extraer los folios (asumiendo que cada 'item' tiene una propiedad 'Folio')
                List<dynamic> init_folios = lstdetalle.Select(item => item.Folio).ToList();

                // Recorrer lstdetalle para generar PDFs o cualquier otra lógica necesaria
                foreach (var item in lstdetalle.GroupBy(x => (object)x.Folio).Select(g => g.First()))
                {
                    await PrintTeso(item);
                }

                // Retornar respuesta exitosa con init_folios
                var response = new InitFoliosResponseDto
                {
                    success = true,
                    message = "Folios obtenidos exitosamente.",
                    init_folios = init_folios
                };

                return Ok(response);
            }
            catch (Exception e)
            {
                // Manejo de excepción
                return BadRequest(new InitFoliosResponseDto
                {
                    success = false,
                    message = e.Message,
                    init_folios = new List<dynamic>()
                });
            }
        }

        [HttpGet("movimientos/{fecha}")]
        public async Task<IActionResult> Movimientos(
            DateTime fecha,
            [FromQuery] string? rut = null,
            [FromQuery] string? folio = null)
        {
            try
            {
                int? rutNumero = null;
                string? rutDigito = null;

                // Usa la caja configurada (102) para filtrar en la BD
                int? teCajaId = _cajaIdBD;

                // ----- Parseo opcional del RUT -----
                if (!string.IsNullOrEmpty(rut))
                {
                    var cleanRut = rut.Replace(".", "").Replace("-", "")
                                      .Trim().ToUpper();
                    if (cleanRut.Length > 1)
                    {
                        rutNumero = int.Parse(cleanRut[..^1]);
                        rutDigito = cleanRut[^1].ToString();
                    }
                }

                // Consulta al repositorio
                var data = await _dbTbk.GetMovimientos(
                    fecha, rutNumero, rutDigito, folio, teCajaId);

                return Ok(data);
            }
            catch (Exception e)
            {
                return BadRequest(new { error = e.Message });
            }
        }

        #endregion

        #region "I Procesos con BD"

        private async Task ActualizaPago(int Folio, SaleResponse data)
        {
            UpdateTransaccionDto datx = new UpdateTransaccionDto();

            datx.CodeStatus = data.ResponseCode.ToString();
            datx.Terminal = data.TerminalId;
            datx.Fecha = DateTime.Now.ToLongDateString();
            datx.Hora = DateTime.Now.ToLongTimeString();
            datx.Tarjeta = data.CardType;
            datx.Cuenta = data.Last4Digits;
            datx.Marca = data.CardBrand;
            datx.Autorizacion = data.AuthorizationCode;
            datx.Operacion = data.OperationNumber.ToString();

            await _dbTbk.UpdateTransaccionAsync(Folio, datx);

            // Impresion comprobante TBK
            PrintTbk(data);

            // Impresion comprobante TESO
            // Obtener detalle de pago
            var datalle = await _dbTbk.GetDetallePago(Folio);

            // Convertir a lista
            var lstdetalle = datalle.ToList();

            foreach (var item in lstdetalle.GroupBy(x => (object)x.Folio).Select(g => g.First()))
            {
                await PrintTeso(item);
            }
        }

        private void NewIntermediateMessageReceived(object sender, IntermediateResponse e)
        {
            int responseCodeToSend = e.ResponseCode;

            if (e.FunctionCode == 900 && e.ResponseCode == 0)
            {
                responseCodeToSend = 81;
            }
            if (e.FunctionCode == 0 && e.ResponseCode == 0)
            {
                responseCodeToSend = 21;
            }

            var message = JsonSerializer.Serialize(new
            {
                FunctionCode = e.FunctionCode,
                ResponseCode = responseCodeToSend,
                // Convertir ResponseMessage a string para evitar la conversión implícita de bool a string
                ResponseMessage = e.ResponseMessage.ToString()
            });

            var buffer = Encoding.UTF8.GetBytes(message);
            lock (_webSocketClients)
            {
                foreach (var client in _webSocketClients)
                {
                    if (client.State == WebSocketState.Open)
                    {
                        _ = client.SendAsync(new ArraySegment<byte>(buffer),
                                               WebSocketMessageType.Text,
                                               true,
                                               CancellationToken.None);
                    }
                }
            }
        }


        private void WsMensajesProcesos(int functionCode, int responseCode, string responseMessage)
        {
            var message = JsonSerializer.Serialize(new      // ← pascal case
            {
                FunctionCode = functionCode,
                ResponseCode = responseCode,
                ResponseMessage = responseMessage
            });
            
            var buffer = Encoding.UTF8.GetBytes(message);
            lock (_webSocketClients)
            {
                foreach (var client in _webSocketClients)
                    if (client.State == WebSocketState.Open)
                        _ = client.SendAsync(new ArraySegment<byte>(buffer),
                                             WebSocketMessageType.Text, true,
                                             CancellationToken.None);
            }
        }


        #endregion

        #region "II Funciones y Procesos"

        private void PrintTbk(SaleResponse data)
        {
            var dataprint = data.PrintingField;

            Printer printer = new Printer(_printerName);

            for (int i = 0; i < dataprint.Count(); i++)
            {
                printer.Append("      " + dataprint[i]);
            }

            printer.FullPaperCut();
            printer.PrintDocument();
        }

        private void PrinCierre(CloseResponse data)
        {
            var dataprint = data.PrintingField;

            Printer printer = new Printer(_printerName);

            for (int i = 0; i < dataprint.Count(); i++)
            {
                printer.Append("      " + dataprint[i]);
            }

            printer.FullPaperCut();
            printer.PrintDocument();
        }

        private async Task PrintTeso(dynamic detalle)
        {
            try
            {
                // Convertir el folio a string para usarlo en el nombre del documento
                string folio = detalle.Folio.ToString();
                string docname = $"Documento_{folio}.pdf";

                // Definir la carpeta donde se generan los PDFs
                string pdfDirectory = Path.Combine(Directory.GetCurrentDirectory(), "GeneratedDocuments");
                // Si la carpeta no existe, créala
                if (!Directory.Exists(pdfDirectory))
                {
                    Directory.CreateDirectory(pdfDirectory);
                }
                // Construir la ruta completa del PDF
                string pdfPath = Path.Combine(pdfDirectory, docname);

                // Si el archivo ya existe, se utiliza y se manda a imprimir sin regenerarlo.
                if (System.IO.File.Exists(pdfPath))
                {
                    WsMensajesProcesos(0, 202, "Documento ya existe, preparando impresora...");
                    WsMensajesProcesos(0, 7777, folio);
                    return;
                }

                // Si no existe, procedemos a generar el PDF.
                WsMensajesProcesos(0, 100, "Iniciando impresión de comprobante");

                // Intentar obtener un GUID válido (con reintentos)
                var guid = await ObtenerGuidValidoAsync();
                if (string.IsNullOrEmpty(guid))
                {
                    WsMensajesProcesos(0, 7, "No se pudo obtener un GUID válido tras varios intentos.");
                    return;
                }

                // Cargar imágenes necesarias para el PDF
                string imagePath = Path.Combine(Directory.GetCurrentDirectory(), "assets", "img", "logo.png");
                byte[] imageData = System.IO.File.ReadAllBytes(imagePath);

                string imagePath2 = Path.Combine(Directory.GetCurrentDirectory(), "assets", "img", "timbre.png");
                byte[] imageData2 = System.IO.File.ReadAllBytes(imagePath2);

                // Generar el código QR usando el GUID obtenido
                string qrData = $"https://plataformafirma.ecertchile.cl/SitioWeb/Consultas/VerDocPDF/{guid}";
                byte[] qrImage = GenerateQrCode(qrData);

                // Crear el documento PDF (sin firma) y generarlo en la ruta indicada
                IDocument document = CrearDocumentoPdf(detalle, qrImage, imageData, imageData2);
                document.GeneratePdf(pdfPath);

                // Verificar que el PDF se haya generado
                if (!System.IO.File.Exists(pdfPath))
                {
                    WsMensajesProcesos(0, 7, "El documento no se encuentra disponible. Por favor, solicita su reimpresión en Tesorería.");
                    return;
                }
                WsMensajesProcesos(0, 103, "Documento PDF generado");

                // Proceder con la firma digital, con hasta 3 reintentos
                FirmaDocumentoResponse documentoFirmado = null;
                bool firmaOk = false;
                int reintentos = 0;
                while (reintentos < 3 && !firmaOk)
                {
                    reintentos++;
                    try
                    {
                        // Intentar firmar el documento
                        documentoFirmado = await FirmarDocumentoAsync(guid, pdfPath);
                        if (documentoFirmado == null)
                        {
                            Console.WriteLine($"[FirmaDocumento] - Falla en intento {reintentos} (documentoFirmado=null)");
                        }
                        else
                        {
                            var xml = XDocument.Parse(documentoFirmado.Body.FirmaDocumentoResult);
                            var docbase64 = xml.Descendants("Contenido").FirstOrDefault()?.Value;
                            if (!string.IsNullOrEmpty(docbase64))
                            {
                                // Decodificar y grabar el PDF firmado
                                var firmadoBytes = Convert.FromBase64String(docbase64);
                                await System.IO.File.WriteAllBytesAsync(pdfPath, firmadoBytes);
                                firmaOk = true;
                            }
                            else
                            {
                                Console.WriteLine($"[FirmaDocumento] - Intento {reintentos}: docbase64 vacío.");
                            }
                        }
                        if (!firmaOk && reintentos < 3)
                        {
                            await Task.Delay(1000);
                        }
                    }
                    catch (Exception ex2)
                    {
                        Console.WriteLine($"[FirmaDocumento] - Excepción en intento {reintentos}: {ex2.Message}");
                        if (reintentos < 3)
                        {
                            await Task.Delay(1000);
                        }
                    }
                }

                if (!firmaOk)
                {
                    WsMensajesProcesos(0, 7, "Fallo al firmar el documento (luego de 3 reintentos).");
                    return;
                }

                WsMensajesProcesos(0, 105, "Documento firmado electrónicamente");

                // Verificar que el documento firmado existe
                if (!System.IO.File.Exists(pdfPath))
                {
                    WsMensajesProcesos(0, 7, "El documento firmado no se encuentra disponible.");
                    return;
                }

                // Enviar la orden para imprimir
                WsMensajesProcesos(0, 202, "Preparando impresora");
                Console.WriteLine("Aquí inicia el Proceso de WsMensajesProcesos");
                WsMensajesProcesos(0, 7777, folio);
            }
            catch (Exception ex)
            {
                WsMensajesProcesos(0, 7, $"Error en la impresión: {ex.Message}");
                Console.WriteLine($"Error al crear el PDF: {ex.Message}");
            }
        }


        private async Task<string> ObtenerGuidValidoAsync(int maxIntentos = 3)
        {
            int intento = 0;
            string guid = string.Empty;

            while (intento < maxIntentos)
            {
                intento++;
                try
                {
                    WsMensajesProcesos(0, 101, $"Solicitando Firma Electronica (Intento {intento} de {maxIntentos})");

                    // Crear una nueva instancia del cliente SOAP
                    using var client = new FirmaIcerServices.FirmaElectronicaSoapClient(
                        new BasicHttpBinding(BasicHttpSecurityMode.Transport),
                        new EndpointAddress("https://plataformafirma.ecertchile.cl/WebService/FirmaElectronica.asmx"));

                    // Llamar al método SOAP
                    var response = await client.SolicitarGuidAsync(_usuario, _clave);

                    // Verificar la respuesta
                    if (response?.Body == null || string.IsNullOrEmpty(response.Body.SolicitarGuidResult))
                    {
                        throw new Exception("La respuesta del servicio está vacía o no contiene datos.");
                    }

                    // Extraer el GUID desde el XML
                    var xml = XDocument.Parse(response.Body.SolicitarGuidResult);
                    guid = xml.Descendants("Guid").FirstOrDefault()?.Value;

                    if (string.IsNullOrEmpty(guid))
                    {
                        throw new Exception("El GUID no se encontró en la respuesta del servicio.");
                    }

                    // Verificar si el GUID es válido
                    WsMensajesProcesos(0, 102, "Firma Autorizada");
                    Console.WriteLine($"[LOG] GUID obtenido en intento {intento}: {guid}");

                    return guid;
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[LOG] Error en FirmaSolicitarGuidAsync (Intento {intento}): {ex.Message}");
                    if (intento < maxIntentos)
                    {
                        await Task.Delay(1000); // Espera 1 segundo (ajusta según tus necesidades)
                    }
                }
            }

            return guid;
        }

        /// <summary>
        /// Método auxiliar para crear el documento PDF con el QR proporcionado.
        /// </summary>
        private IDocument CrearDocumentoPdf(dynamic detalle, byte[] qrImage, byte[] imageData, byte[] imageData2)
        {
            string _folio = detalle.Folio != null ? detalle.Folio.ToString() : "";
            string _rut = $"{detalle.RutNumero}-{detalle.RutDigito}";
            string _razonSocial = detalle.Nombres != null ? detalle.Nombres.ToString() : "";
            string _direccion = detalle.Direccion != null ? detalle.Direccion.ToString() : "";
            string _boletin = detalle.Boletin != null ? detalle.Boletin.ToString() : "";
            string _tramite = detalle.Glosa != null ? detalle.Glosa.ToString() : "";
            // Validamos cada propiedad crítica para evitar el error de runtime binding
            string _tbk_operacion = detalle.tbk_operacion != null ? detalle.tbk_operacion.ToString() : "";
            string _tbk_autorizacion = detalle.tbk_autorizacion != null ? detalle.tbk_autorizacion.ToString() : "";
            string _tbk_tarjeta = detalle.tbk_tarjeta != null ? detalle.tbk_tarjeta.ToString() : "";
            string _tbk_cuenta = detalle.tbk_cuenta != null ? detalle.tbk_cuenta.ToString() : "";
            string _fechaPago = detalle.init_fecha != null ? detalle.init_fecha.ToString("dd/MM/yyyy") : ""; // este llega null
            string _Monto = detalle.Monto != null ? detalle.Monto.ToString("N0") : "0";
            string _Reajuste = detalle.Reajuste != null ? detalle.Reajuste.ToString("N0") : "0";
            string _Intereses = detalle.Intereses != null ? detalle.Intereses.ToString("N0") : "0";
            string _Total = detalle.Total != null ? detalle.Total.ToString("N0") : "0";
            string numeroCaja = detalle.NumeroCaja != null
                ? detalle.NumeroCaja.ToString()
                : (!string.IsNullOrEmpty(_numeroCaja) ? _numeroCaja : "Sin Especificar");

            return Document.Create(ctx =>
            {
                ctx.Page(page =>
                {
                    page.Size(PageSizes.Letter);
                    page.Margin(2, Unit.Centimetre);
                    page.DefaultTextStyle(TextStyle.Default.FontSize(10));

                    // Encabezado con logo e imagen QR
                    page.Header().Row(row =>
                    {
                        row.RelativeItem().Column(column =>
                        {
                        });

                        row.ConstantItem(100).Height(100).Image(qrImage);
                    });

                    // Contenido principal del PDF
                    page.Content().Column(column =>
                    {
                        column.Spacing(10);

                        // Título centrado
                        column.Item()
                              .AlignCenter() // Alineación aplicada al contenedor
                              .Text("COMPROBANTE DERECHOS VARIOS")
                              .FontSize(15)
                              .Bold();

                        // Sección: Contribuyente
                        column.Item().Text(text =>
                        {
                            text.DefaultTextStyle(TextStyle.Default.FontSize(12).Bold());
                            text.AlignLeft();
                            text.Line("CONTRIBUYENTE :");
                        });

                        column.Item().Text(text =>
                        {
                            text.DefaultTextStyle(TextStyle.Default.FontSize(12).Bold());
                            text.AlignRight();
                            text.Line($"FOLIO : {_folio}");
                        });

                        // Tabla de información del contribuyente
                        column.Item().Table(table =>
                        {
                            table.ColumnsDefinition(columns =>
                            {
                                columns.RelativeColumn(1);
                                columns.RelativeColumn(2);
                            });

                            table.Cell().Border(1).Text("Rut:");
                            table.Cell().Border(1).Text(_rut);

                            table.Cell().Border(1).Text("Nombre/Razón Social:");
                            table.Cell().Border(1).Text(_razonSocial);

                            table.Cell().Border(1).Text("Domicilio:");
                            table.Cell().Border(1).Text(_direccion);
                        });

                        // Sección: Tipo Pago
                        column.Item().Text(text =>
                        {
                            text.DefaultTextStyle(TextStyle.Default.FontSize(12).Bold());
                            text.AlignLeft();
                            text.Line("TIPO PAGO :");
                        });

                        // Tabla de tipo de pago
                        column.Item().Table(table =>
                        {
                            table.ColumnsDefinition(columns =>
                            {
                                columns.RelativeColumn(1);
                                columns.RelativeColumn(3);
                            });

                            table.Cell().Border(1).Text("Por concepto de:");
                            table.Cell().Border(1).Text(_boletin);

                            table.Cell().Border(1).Text("GLOSA:");
                            table.Cell().Border(1).Text(_tramite);
                        });

                        // Sección: Detalle de Pago
                        column.Item().Text(text =>
                        {
                            text.DefaultTextStyle(TextStyle.Default.FontSize(12).Bold());
                            text.AlignLeft();
                            text.Line("DETALLE DE PAGO :");
                        });

                        // Detalles de pago y timbre
                        column.Item().Row(row =>
                        {
                            var tableHeight = 200; // Altura deseada para ambas columnas

                            // Tabla de detalles de pago
                            row.RelativeItem(1).Height(tableHeight).Table(table =>
                            {
                                table.ColumnsDefinition(columns =>
                                {
                                    columns.RelativeColumn(1); // Más espacio para nombres
                                    columns.RelativeColumn(1); // Menos espacio para valores
                                });

                                table.Cell().Border(1).Text("Código de Transacción:");
                                table.Cell().Border(1).Text(_tbk_operacion);

                                table.Cell().Border(1).Text("Código de Autorización:");
                                table.Cell().Border(1).Text(_tbk_autorizacion);

                                table.Cell().Border(1).Text("Modalidad de Pago:");
                                table.Cell().Border(1).Text(_tbk_tarjeta);

                                table.Cell().Border(1).Text("Número de Tarjeta:");
                                table.Cell().Border(1).Text($"XXXX-XXXX-XXXX-{_tbk_cuenta}");

                                table.Cell().Border(1).Text("Fecha de Pago:");
                                table.Cell().Border(1).Text(_fechaPago);

                                table.Cell().Border(1).Text("Sub Total:");
                                table.Cell().Border(1).Text($"${_Monto}");

                                table.Cell().Border(1).Text("Interés:");
                                table.Cell().Border(1).Text($"${_Intereses}");

                                table.Cell().Border(1).Text("Reajuste:");
                                table.Cell().Border(1).Text($"${_Reajuste}");

                                table.Cell().Border(1).Text("Total:");
                                table.Cell().Border(1).Text($"${_Total}");
                            });

                            // Tabla para el timbre y detalles adicionales
                            row.RelativeItem(1).Height(tableHeight).Table(table =>
                            {
                                table.ColumnsDefinition(columns =>
                                {
                                    columns.RelativeColumn(1); // Define una única columna con ancho relativo
                                });

                                table.Cell().Border(1).AlignCenter().AlignMiddle().Element(cell =>
                                {
                                    cell.Layers(layer =>
                                    {
                                        // Capa primaria: Imagen del timbre
                                        layer.PrimaryLayer()
                                            .AlignCenter()
                                            .AlignMiddle()
                                            .Padding(0) // Reducir el relleno
                                            .Column(column =>
                                            {
                                                column.Item().Width(100).Image(imageData2);
                                            });

                                        // Capa secundaria: Textos sobre la imagen
                                        layer.Layer()
                                            .AlignCenter()
                                            .AlignMiddle()
                                            .Column(column =>
                                            {
                                                column.Item().AlignCenter().Text(_numeroCaja);
                                                column.Item().AlignCenter().Text("PAGADO");
                                                column.Item().AlignCenter().Text(_fechaPago);
                                            });
                                    });
                                });
                            });
                        });
                    });
                });
            });
        }

        #endregion

        #region "III Funciones Auxiliares"

        /// <summary>
        /// Método auxiliar para generar el código QR.
        /// </summary>
        private byte[] GenerateQrCode(string qrData)
        {
            using (var generator = new QRCodeGenerator())
            {
                QRCodeData qrCodeData = generator.CreateQrCode(qrData, QRCodeGenerator.ECCLevel.Q);
                PngByteQRCode qrCode = new PngByteQRCode(qrCodeData);
                return qrCode.GetGraphic(100); // Devuelve el QR como byte[]
            }
        }

        private async Task<string> FirmaSolicitarGuidAsync(int maxIntentos = 3)
        {
            int intento = 0;
            while (intento < maxIntentos)
            {
                intento++;
                try
                {
                    WsMensajesProcesos(0, 101, $"Solicitando Firma Electronica (Intento {intento} de {maxIntentos})");

                    // Crear una nueva instancia del cliente SOAP
                    using var client = new FirmaIcerServices.FirmaElectronicaSoapClient(
                        new BasicHttpBinding(BasicHttpSecurityMode.Transport),
                        new EndpointAddress("https://plataformafirma.ecertchile.cl/WebService/FirmaElectronica.asmx"));

                    // Llamar al método SOAP
                    var response = await client.SolicitarGuidAsync(_usuario, _clave);

                    // Verificar la respuesta
                    if (response?.Body == null || string.IsNullOrEmpty(response.Body.SolicitarGuidResult))
                    {
                        throw new Exception("La respuesta del servicio está vacía o no contiene datos.");
                    }

                    // Extraer el GUID desde el XML
                    var xml = XDocument.Parse(response.Body.SolicitarGuidResult);
                    var guid = xml.Descendants("Guid").FirstOrDefault()?.Value;

                    if (string.IsNullOrEmpty(guid))
                    {
                        throw new Exception("El GUID no se encontró en la respuesta del servicio.");
                    }

                    WsMensajesProcesos(0, 102, "Firma Autorizada");
                    Console.WriteLine($"[LOG] GUID obtenido en intento {intento}: {guid}");
                    return guid;
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[LOG] Error en FirmaSolicitarGuidAsync (Intento {intento}): {ex.Message}");
                    // Si no se alcanzó el máximo de intentos, esperar un poco antes de reintentar (opcional)
                    if (intento < maxIntentos)
                    {
                        await Task.Delay(1000); // Espera 1 segundo (ajusta según tus necesidades)
                    }
                }
            }

            // Si se agotaron los intentos, puedes devolver una cadena vacía o lanzar una excepción
            WsMensajesProcesos(9999, 9999, "No se pudo obtener un GUID válido tras varios intentos.");
            return "";
        }

        private async Task<FirmaDocumentoResponse> FirmarDocumentoAsync(string guid, string pdfPath)
        {
            try
            {
                // Crear una nueva instancia del cliente con un Binding personalizado
                var binding = new BasicHttpBinding(BasicHttpSecurityMode.Transport)
                {
                    MaxReceivedMessageSize = 20000000, // Aumentar el tamaño máximo del mensaje
                    ReaderQuotas = new System.Xml.XmlDictionaryReaderQuotas
                    {
                        MaxDepth = 32,
                        MaxStringContentLength = 20000000,
                        MaxArrayLength = 20000000,
                        MaxBytesPerRead = 4096,
                        MaxNameTableCharCount = 20000000
                    }
                };

                using var client = new FirmaIcerServices.FirmaElectronicaSoapClient(
                    binding,
                    new EndpointAddress("https://plataformafirma.ecertchile.cl/WebService/FirmaElectronica.asmx"));

                // Convertir el archivo PDF a Base64
                var base_64_pdf = ConvertPdfToBase64(pdfPath);

                // Crear el sobre XML
                var sobreXML = $@"
                    <Sobre>
                        <Cabecera>
                            <Firmantes>
                                <DatosFirmante>
                                    <Rut>{_rutFirma}</Rut>
                                </DatosFirmante>
                            </Firmantes>
                        </Cabecera>
                        <Documentos>
                            <DatosDocumento tipo=""PDF"" Codigo=""{_codigoBin}"">
                                <Contenido>
                                    {base_64_pdf}
                                </Contenido>
                                <CodigoGUID>{guid}</CodigoGUID>
                                <PosIzq>230</PosIzq>
                                <PosInf>100</PosInf>
                                <PosAncho>800</PosAncho>
                                <PosLargo>800</PosLargo>
                            </DatosDocumento>
                        </Documentos>
                    </Sobre>";

                // Llamar al método SOAP
                var response = await client.FirmaDocumentoAsync(_usuario, _clave, sobreXML);

                // Verificar si la respuesta es válida
                if (response?.Body == null || string.IsNullOrEmpty(response.Body.FirmaDocumentoResult))
                {
                    throw new Exception("La respuesta del servicio está vacía o no contiene resultados.");
                }

                return response;
            }
            catch (Exception ex)
            {
                WsMensajesProcesos(9999, 9999, ex.Message);
                return null;
            }
        }

        private string ConvertPdfToBase64(string pdfPath)
        {
            if (!System.IO.File.Exists(pdfPath))
            {
                throw new FileNotFoundException($"El archivo PDF no se encontró en la ruta especificada: {pdfPath}");
            }

            byte[] pdfBytes = System.IO.File.ReadAllBytes(pdfPath);
            return Convert.ToBase64String(pdfBytes);
        }

        private async Task<bool> TryOpenPortAsync(string portName, string folio, int maxRetries = 3, int delayMilliseconds = 1000)
        {
            int attempts = 0;
            while (attempts < maxRetries)
            {
                try
                {
                    await _dbTbk.InsertLogAsync(folio, $"Intentando abrir el puerto {portName}. Intento {attempts + 1} de {maxRetries}.");
                    POSAutoservicio.Instance.OpenPort(portName);
                    return true;
                }
                catch (Exception ex)
                {
                    attempts++;
                    await _dbTbk.InsertLogAsync(folio, $"Error al abrir puerto {portName} en intento {attempts}: {ex.Message}");
                    WsMensajesProcesos(0, 701, $"Error al abrir el puerto {portName}. Intento {attempts} de {maxRetries}.");
                    if (attempts < maxRetries)
                    {
                        await Task.Delay(delayMilliseconds);
                    }
                }
            }
            return false;
        }




        #endregion
    }
}
