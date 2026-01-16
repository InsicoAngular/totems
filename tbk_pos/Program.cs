using FirmaIcerServices;
using System.Net.WebSockets;
using System.ServiceModel;
using tbk_pos.infractructure.repository;

var builder = WebApplication.CreateBuilder(args);

// Registrar cliente SOAP
builder.Services.AddScoped<FirmaElectronicaSoapClient>(serviceProvider =>
{
    var endpoint = new EndpointAddress(builder.Configuration["FirmaElectronicaService:UrlServicio"]);
    var binding = new BasicHttpBinding(BasicHttpSecurityMode.Transport)
    {
        MaxReceivedMessageSize = 20000000 // Ajusta según sea necesario
    };
    return new FirmaElectronicaSoapClient(binding, endpoint);
});

// Agrega servicios al contenedor
builder.Services.AddSingleton<IConfiguration>(builder.Configuration);
builder.Services.AddScoped<dbTbk>();

// Configura CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader()
              .SetPreflightMaxAge(TimeSpan.FromMinutes(10)); // Optimiza preflight requests
    });
});

// Configura JSON para case insensitive
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNameCaseInsensitive = true;
    });

// Agregar Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Almacén de clientes WebSocket (como servicio singleton)
builder.Services.AddSingleton<List<WebSocket>>();

var app = builder.Build();

// Configuración de Swagger
app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "V1 Docs");
});

// Habilitar soporte para WebSockets
app.UseWebSockets();

// Usar CORS con la política configurada antes de otros middlewares
app.UseCors("AllowAll");

// Redirección HTTPS
app.UseHttpsRedirection();
app.UseAuthorization();

// Mapea controladores
app.MapControllers();

if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();   // muestra la traza completa en el navegador/Postman
}


// Endpoint para manejar conexiones WebSocket
app.Map("/ws", async context =>
{
    var webSocketClients = context.RequestServices.GetRequiredService<List<WebSocket>>();

    if (context.WebSockets.IsWebSocketRequest)
    {
        var webSocket = await context.WebSockets.AcceptWebSocketAsync();
        lock (webSocketClients)
        {
            webSocketClients.Add(webSocket);
        }

        await HandleWebSocketConnection(webSocket, webSocketClients);
    }
    else
    {
        context.Response.StatusCode = 400;
    }
});

async Task HandleWebSocketConnection(WebSocket webSocket, List<WebSocket> clients)
{
    var buffer = new byte[1024 * 4];

    try
    {
        while (webSocket.State == WebSocketState.Open)
        {
            var result = await webSocket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                lock (clients)
                {
                    clients.Remove(webSocket);
                }
                await webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, string.Empty, CancellationToken.None);
            }
        }
    }
    catch
    {
        lock (clients)
        {
            clients.Remove(webSocket);
        }
    }
}

app.Run();
