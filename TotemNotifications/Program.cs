using System;
using System.Linq;                       // 👈 falta este
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.OpenApi.Models;
using TotemNotifications.Services;

var builder = WebApplication.CreateBuilder(args);

/* ───────────────────── Services ───────────────────── */

builder.Services.AddSingleton<NotificationService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<NotificationService>());

builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
    p.AllowAnyHeader()
     .AllowAnyMethod()
     .AllowCredentials()
     .WithOrigins("http://localhost:3000")));

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Totem Notifications API",
        Version = "v1",
        Description = "Health y WebSocket endpoints para los tótems de llamados."
    });
});

var app = builder.Build();

/* ─────────────────── Middleware ─────────────────── */

app.UseCors();

app.UseWebSockets(new WebSocketOptions
{
    KeepAliveInterval = TimeSpan.FromSeconds(30) // 15–30 s está bien
});

app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Totem Notifications API v1");
    c.RoutePrefix = "swagger";
});

/* ─────────────────── Endpoints HTTP ─────────────────── */

app.MapGet("/", () => Results.Redirect("/swagger"));

app.MapGet("/health", () => Results.Ok("ok"))
   .WithName("Health")
   .WithOpenApi(op =>
   {
       op.Summary = "Revisa el estado del servicio";
       op.Description = "Devuelve 200 OK con el cuerpo \"ok\" si la app está en ejecución.";
       return op;
   });

/* ─────────────────── WebSockets ─────────────────── */

app.Map("/ws", async (HttpContext ctx, NotificationService hub) =>
{
    if (!ctx.WebSockets.IsWebSocketRequest)
    {
        ctx.Response.StatusCode = StatusCodes.Status400BadRequest;
        await ctx.Response.WriteAsync("WebSocket expected");
        return;
    }

    var ws = await ctx.WebSockets.AcceptWebSocketAsync();
    await hub.HandleClientAsync(ws);
});

app.Map("/ws/tickets", async (HttpContext ctx, NotificationService hub) =>
{
    if (!ctx.WebSockets.IsWebSocketRequest)
    {
        ctx.Response.StatusCode = StatusCodes.Status400BadRequest;
        await ctx.Response.WriteAsync("WebSocket expected");
        return;
    }

    var ws = await ctx.WebSockets.AcceptWebSocketAsync();
    await hub.HandleClientAsync(ws);
});

app.MapGet("/api/llamados/estado", async (NotificationService svc) =>
{
    var list = await svc.GetLatestTicketsForDefaultsAsync();
    var actual = list.FirstOrDefault();
    var historial = list.Skip(1).Take(2).ToList();
    return Results.Json(new { actual, historial });
});

app.Run();
