using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;

namespace TotemNotifications.Services
{
    /// Servicio WS con SqlDependency (ALCLLAMADOS).
    /// - Re-suscribe con retry/backoff
    /// - Safety-poll por si se pierde un notification
    /// - Provee snapshot público para REST fallback
    public class NotificationService : IHostedService, IDisposable
    {
        private readonly string _connStr;

        // socket + filtros del cliente
        private readonly ConcurrentDictionary<string, (WebSocket socket, ClientFilters filters)> _clients = new();

        // SqlDependency infra
        private SqlDependency? _dependency;
        private SqlConnection? _conn;

        // heartbeat a clientes
        private readonly TimeSpan _pingInterval = TimeSpan.FromSeconds(25);
        private Timer? _pingTimer;
        private static readonly byte[] PingMsg = Encoding.UTF8.GetBytes("🫀");

        // safety-poll a la DB (por si SqlDependency se pierde)
        private readonly TimeSpan _pollInterval = TimeSpan.FromSeconds(5);
        private Timer? _pollTimer;
        private int _lastMaxId = 0;

        // Defaults desde appsettings: Filter.*
        private HashSet<string> _defaultTypes;
        private readonly List<string> _defaultFamilies;
        private readonly string? _defaultPrefix;
        private readonly HashSet<int> _defaultTerminalIds;
        private readonly int _topPerTipo;

        private readonly JsonSerializerOptions _jsonOpts = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };

        public NotificationService(IConfiguration configuration)
        {
            _connStr = configuration.GetConnectionString("DefaultConnection")!;

            var f = configuration.GetSection("Filter");
            _defaultTypes = ParseTypes(f["Types"]);
            _defaultFamilies = ParseCsvUpper(f["Family"] ?? f["Families"]);
            _defaultPrefix = NullIfEmpty(f["Prefix"])?.ToUpperInvariant();
            _defaultTerminalIds = ParseIds(f["TerminalIds"]);
            _topPerTipo = int.TryParse(f["TopPerTipo"], out var n) && n > 0 ? n : 3;

            // Compat: TIPO_ESPERA legado
            if (_defaultTypes.Count == 0)
            {
                var legacy = NullIfEmpty(configuration["TIPO_ESPERA"]);
                if (!string.IsNullOrWhiteSpace(legacy) && legacy != "*")
                    _defaultTypes = ParseTypes(legacy);
            }
        }

        /*──────────────────── Helpers filtros ────────────────────*/
        private static string? NullIfEmpty(string? s) => string.IsNullOrWhiteSpace(s) ? null : s;

        private static HashSet<string> ParseTypes(string? s)
        {
            s = s?.Trim();
            if (string.IsNullOrEmpty(s) || s == "*") return new(); // “todos”
            return s.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                    .Select(x => x.Substring(0, 1).ToUpperInvariant())
                    .ToHashSet(StringComparer.Ordinal);
        }

        private static List<string> ParseCsvUpper(string? s)
        {
            if (string.IsNullOrWhiteSpace(s)) return new();
            return s.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                    .Select(x => x.ToUpperInvariant()).ToList();
        }

        private static HashSet<int> ParseIds(string? s)
        {
            var set = new HashSet<int>();
            if (string.IsNullOrWhiteSpace(s)) return set;
            foreach (var part in s.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                if (int.TryParse(part, out var id)) set.Add(id);
            return set;
        }

        /*──────────────────── Ciclo de vida ────────────────────*/
        public Task StartAsync(CancellationToken ct)
        {
            // Inicia Query Notifications
            SqlDependency.Start(_connStr);

            // Suscripción inicial (con retry no-bloqueante)
            _ = SubscribeWithRetryAsync();

            // Heartbeat WS
            _pingTimer = new Timer(state => { _ = BroadcastPingAsync(); }, null, _pingInterval, _pingInterval);

            // Safety-poll
            _pollTimer = new Timer(async state =>
            {
                try
                {
                    var list = await GetLatestTicketsForDefaultsAsync();
                    var max = list.Count == 0 ? 0 : list.Max(x => (int)x.GetType().GetProperty("id")!.GetValue(x)!);
                    if (max > _lastMaxId)
                    {
                        _lastMaxId = max;
                        await BroadcastLatestTicketsAsync();
                    }
                }
                catch { /* silencio: reintenta el próximo tick */ }
            }, null, _pollInterval, _pollInterval);

            Console.WriteLine("✅ NotificationService iniciado.");
            return Task.CompletedTask;
        }

        public Task StopAsync(CancellationToken ct)
        {
            _pingTimer?.Dispose(); _pingTimer = null;
            _pollTimer?.Dispose(); _pollTimer = null;

            try { SqlDependency.Stop(_connStr); } catch { /* ignore */ }
            try { _conn?.Dispose(); } catch { /* ignore */ }
            _conn = null;

            Console.WriteLine("🛑 NotificationService detenido");
            return Task.CompletedTask;
        }

        public void Dispose()
        {
            // Cierra ordenadamente
            StopAsync(CancellationToken.None).GetAwaiter().GetResult();
        }

        /*──────────────────── SqlDependency ────────────────────*/
        private void EnsureConn()
        {
            if (_conn is { State: ConnectionState.Open }) return;
            _conn?.Dispose();
            _conn = new SqlConnection(_connStr);
            _conn.Open();
        }

        private async Task SubscribeWithRetryAsync()
        {
            var delay = 1000;
            while (true)
            {
                try
                {
                    Subscribe();
                    return;
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"❌ Subscribe() falló: {ex.Message}. Reintentando en {delay}ms");
                    await Task.Delay(delay);
                    delay = Math.Min(delay * 2, 15000);
                }
            }
        }

        private void Subscribe()
        {
            try
            {
                if (_dependency != null) _dependency.OnChange -= OnSqlChange;

                EnsureConn();

                // Consulta mínima válida para Query Notifications
                const string NotifQuery = @"
SELECT id
FROM   dbo.ALCLLAMADOS
WHERE  Fecha = @today;";

                using var cmd = new SqlCommand(NotifQuery, _conn);
                cmd.Parameters.Add("@today", SqlDbType.Char, 8).Value = DateTime.Today.ToString("yyyyMMdd");

                _dependency = new SqlDependency(cmd);
                _dependency.OnChange += OnSqlChange;

                using var reader = cmd.ExecuteReader(); // activa subscripción
                while (reader.Read()) { /* noop */ }

                Console.WriteLine($"🔔 Suscrito OK @ {DateTime.Now:T}");
            }
            catch
            {
                // Propaga y que lo maneje SubscribeWithRetryAsync()
                throw;
            }
        }

        private void OnSqlChange(object? sender, SqlNotificationEventArgs e)
        {
            try { _dependency!.OnChange -= OnSqlChange; } catch { /* ignore */ }

            Console.WriteLine($"SqlDependency → Type={e.Type}, Info={e.Info}, Source={e.Source}");

            if (e.Type == SqlNotificationType.Change)
                _ = BroadcastLatestTicketsAsync(); // fire & forget

            // Re-suscribe SIEMPRE (si fue inválida, que el retry lo intente de nuevo)
            _ = SubscribeWithRetryAsync();
        }

        /*──────────────────── API pública para REST ────────────────────*/
        public Task<List<object>> GetLatestTicketsForDefaultsAsync()
            => FetchLatestTicketsAsync(_defaultTypes, _defaultFamilies, _defaultPrefix, _defaultTerminalIds, _topPerTipo);

        /*──────────────────── Query (ALCLLAMADOS) ────────────────────*/
        private async Task<List<object>> FetchLatestTicketsAsync(
            HashSet<string> types,
            List<string> families,
            string? prefix,
            HashSet<int> terminalIds,
            int topPerTipo)
        {
            EnsureConn();

            var where = new List<string>
            {
                "l.Fecha = CONVERT(char(8), GETDATE(), 112)",
                "(l.NombreCompleto IS NOT NULL AND LTRIM(RTRIM(l.NombreCompleto)) <> '')"
            };

            // Tipos (S/M/P/…)
            var tipoParams = new List<string>();
            var tArr = types.ToArray();
            if (tArr.Length > 0)
            {
                for (int i = 0; i < tArr.Length; i++) tipoParams.Add($"@t{i}");
                where.Add($"l.Tipo_Espera IN ({string.Join(",", tipoParams)})");
            }

            // Families: OR de prefijos sobre Nombre_terminal
            var famParams = new List<string>();
            if (families.Count > 0)
            {
                var famOrs = new List<string>();
                for (int i = 0; i < families.Count; i++)
                {
                    famParams.Add($"@fam{i}");
                    famOrs.Add($"UPPER(l.Nombre_terminal) LIKE @fam{i}");
                }
                where.Add("(" + string.Join(" OR ", famOrs) + ")");
            }

            // Prefix adicional (AND)
            if (!string.IsNullOrEmpty(prefix))
                where.Add("UPPER(l.Nombre_terminal) LIKE @prefixLike");

            // TerminalIds
            var idParams = new List<string>();
            var idArr = terminalIds.ToArray();
            if (idArr.Length > 0)
            {
                for (int i = 0; i < idArr.Length; i++) idParams.Add($"@id{i}");
                where.Add($"l.id_terminal IN ({string.Join(",", idParams)})");
            }

            var sql = $@"
WITH x AS (
  SELECT
      l.id,
      l.NombreCompleto  AS nombre,
      l.Nombre_terminal AS station,
      l.Tipo_Espera     AS tipoEspera,
      ROW_NUMBER() OVER (PARTITION BY l.Tipo_Espera ORDER BY l.id DESC) AS rn
  FROM dbo.ALCLLAMADOS l
  WHERE {string.Join(" AND ", where)}
)
SELECT id, nombre, station, tipoEspera
FROM x
WHERE rn <= @top
ORDER BY id DESC;";

            using var cmd = new SqlCommand(sql, _conn);

            // tipos
            for (int i = 0; i < tArr.Length; i++)
                cmd.Parameters.Add(tipoParams[i], SqlDbType.Char, 1).Value = tArr[i];

            // families
            for (int i = 0; i < families.Count; i++)
                cmd.Parameters.Add(famParams[i], SqlDbType.VarChar, 100).Value = families[i] + "%";

            // prefix
            if (!string.IsNullOrEmpty(prefix))
                cmd.Parameters.Add("@prefixLike", SqlDbType.VarChar, 100).Value = prefix.ToUpperInvariant() + "%";

            // terminal ids
            for (int i = 0; i < idArr.Length; i++)
                cmd.Parameters.Add(idParams[i], SqlDbType.Int).Value = idArr[i];

            cmd.Parameters.Add("@top", SqlDbType.Int).Value = topPerTipo;

            var list = new List<object>();
            using var rdr = await cmd.ExecuteReaderAsync();
            while (await rdr.ReadAsync())
            {
                var id = rdr.GetInt32(0);
                if (id > _lastMaxId) _lastMaxId = id;

                list.Add(new
                {
                    id,
                    name = rdr.IsDBNull(1) ? "" : rdr.GetString(1),
                    station = rdr.IsDBNull(2) ? "" : rdr.GetString(2),
                    isManual = false,
                    tipoEspera = rdr.IsDBNull(3) ? "" : rdr.GetString(3),
                });
            }
            return list;
        }

        /*──────────────────── WebSocket: cliente ────────────────────*/
        public async Task HandleClientAsync(WebSocket socket)
        {
            var id = Guid.NewGuid().ToString();

            // defaults desde appsettings
            var filters = new ClientFilters
            {
                Types = new HashSet<string>(_defaultTypes, StringComparer.Ordinal),
                Families = new List<string>(_defaultFamilies),
                Prefix = _defaultPrefix,
                TerminalIds = new HashSet<int>(_defaultTerminalIds),
                Top = _topPerTipo
            };

            // handshake opcional (puede venir JSON con overrides)
            var buffer = new byte[2048];
            try
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                var res = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), cts.Token);
                if (res.MessageType == WebSocketMessageType.Text && res.Count > 0)
                {
                    var txt = Encoding.UTF8.GetString(buffer, 0, res.Count).Trim();
                    if (txt.StartsWith("{"))
                    {
                        try
                        {
                            using var doc = JsonDocument.Parse(txt);
                            var root = doc.RootElement;

                            if (root.TryGetProperty("types", out var arr) && arr.ValueKind == JsonValueKind.Array)
                                filters.Types = arr.EnumerateArray().Where(e => e.ValueKind == JsonValueKind.String)
                                                .Select(e => e.GetString()!.Substring(0, 1).ToUpperInvariant())
                                                .ToHashSet(StringComparer.Ordinal);

                            if (root.TryGetProperty("families", out var famArr) && famArr.ValueKind == JsonValueKind.Array)
                                filters.Families = famArr.EnumerateArray().Where(e => e.ValueKind == JsonValueKind.String)
                                                 .Select(e => e.GetString()!.ToUpperInvariant()).ToList();

                            if (root.TryGetProperty("family", out var famStr) && famStr.ValueKind == JsonValueKind.String)
                            {
                                var list = ParseCsvUpper(famStr.GetString());
                                if (list.Count > 0) filters.Families = list;
                            }

                            if (root.TryGetProperty("prefix", out var pEl) && pEl.ValueKind == JsonValueKind.String)
                                filters.Prefix = NullIfEmpty(pEl.GetString())?.ToUpperInvariant();

                            if (root.TryGetProperty("terminalIds", out var iEl))
                            {
                                if (iEl.ValueKind == JsonValueKind.Array)
                                    filters.TerminalIds = iEl.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Number)
                                                            .Select(x => x.GetInt32()).ToHashSet();
                                else if (iEl.ValueKind == JsonValueKind.String)
                                    filters.TerminalIds = ParseIds(iEl.GetString());
                            }

                            if (root.TryGetProperty("top", out var tEl) && tEl.ValueKind == JsonValueKind.Number)
                                filters.Top = Math.Max(1, tEl.GetInt32());
                        }
                        catch { /* mantiene defaults */ }
                    }
                    else
                    {
                        // compat: "S,M,P" → solo types
                        filters.Types = txt.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                                           .Select(s => s.Substring(0, 1).ToUpperInvariant())
                                           .ToHashSet(StringComparer.Ordinal);
                    }
                }
            }
            catch { /* timeout: defaults */ }

            _clients[id] = (socket, filters);
            Console.WriteLine($"➕ WS conectado ({id}) {filters}");

            await SendTicketsToClientAsync(id);

            try
            {
                while (socket.State == WebSocketState.Open)
                {
                    var res = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None);
                    if (res.MessageType == WebSocketMessageType.Close) break;
                    // si quisieras, podrías actualizar last-seen aquí
                }
            }
            finally
            {
                await GracefulCloseAsync(socket, "client loop ended");
                _clients.TryRemove(id, out _);
                Console.WriteLine($"❌ WS desconectado ({id})");
            }
        }

        /*──────────────────── Broadcast ────────────────────*/
        private async Task BroadcastLatestTicketsAsync()
        {
            var dead = new List<string>();

            // Agrupa por combinación de filtros (evita repetir la misma query)
            var grupos = _clients.GroupBy(kv => ComposeKey(kv.Value.filters));

            foreach (var g in grupos)
            {
                var f = g.First().Value.filters;
                var tickets = await FetchLatestTicketsAsync(f.Types, f.Families, f.Prefix, f.TerminalIds, f.Top);
                var buf = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(tickets, _jsonOpts));

                foreach (var (id, (socket, _)) in g)
                {
                    if (socket.State != WebSocketState.Open) { dead.Add(id); continue; }
                    try { await socket.SendAsync(buf, WebSocketMessageType.Text, true, CancellationToken.None); }
                    catch { dead.Add(id); }
                }
            }

            Cleanup(dead);
            Console.WriteLine($"📤 Broadcast completado. Clientes vivos: {_clients.Count}");
        }

        private async Task BroadcastPingAsync()
        {
            var dead = new List<string>();
            foreach (var (id, (ws, _)) in _clients)
            {
                if (ws.State != WebSocketState.Open) { dead.Add(id); continue; }
                try { await ws.SendAsync(PingMsg, WebSocketMessageType.Text, true, CancellationToken.None); }
                catch { dead.Add(id); }
            }
            Cleanup(dead);
        }

        private async Task SendTicketsToClientAsync(string id)
        {
            if (!_clients.TryGetValue(id, out var tuple)) return;
            var f = tuple.filters;
            var tickets = await FetchLatestTicketsAsync(f.Types, f.Families, f.Prefix, f.TerminalIds, f.Top);
            var buf = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(tickets, _jsonOpts));

            var socket = tuple.socket;
            if (socket.State == WebSocketState.Open)
            {
                try { await socket.SendAsync(buf, WebSocketMessageType.Text, true, CancellationToken.None); }
                catch { Cleanup(new[] { id }); }
            }
        }

        private void Cleanup(IEnumerable<string> ids)
        {
            foreach (var id in ids)
            {
                if (_clients.TryRemove(id, out var tuple))
                {
                    var ws = tuple.socket;
                    try { ws.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "bye", CancellationToken.None).Wait(); } catch { }
                    try { ws.Abort(); } catch { }
                    try { ws.Dispose(); } catch { }
                    Console.WriteLine($"❌ WS desconectado ({id})");
                }
            }
        }

        /*──────────────────── Utilitarios ────────────────────*/
        private static string ComposeKey(ClientFilters f)
        {
            var t = string.Join(",", f.Types.OrderBy(x => x, StringComparer.Ordinal));
            var ids = string.Join(",", f.TerminalIds.OrderBy(x => x));
            var fam = f.Families.Count == 0 ? "-" : string.Join("|", f.Families.OrderBy(x => x));
            var pre = f.Prefix ?? "-";
            return $"types:{t}|families:{fam}|prefix:{pre}|ids:{ids}|top:{f.Top}";
        }

        private sealed class ClientFilters
        {
            public HashSet<string> Types { get; set; } = new(StringComparer.Ordinal);
            public List<string> Families { get; set; } = new();
            public string? Prefix { get; set; }
            public HashSet<int> TerminalIds { get; set; } = new();
            public int Top { get; set; } = 3;

            public override string ToString()
            {
                var t = Types.Count == 0 ? "*" : string.Join(",", Types.OrderBy(x => x));
                var fam = Families.Count == 0 ? "-" : string.Join("|", Families);
                var ids = TerminalIds.Count == 0 ? "-" : string.Join(",", TerminalIds.OrderBy(x => x));
                return $"types=[{t}], families={fam}, prefix={(Prefix ?? "-")}, ids=[{ids}], top={Top}";
            }
        }

        private static async Task GracefulCloseAsync(WebSocket ws, string reason = "bye")
        {
            try
            {
                if (ws.State == WebSocketState.Open || ws.State == WebSocketState.CloseReceived)
                    await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, reason, CancellationToken.None);
                else if (ws.State == WebSocketState.CloseSent)
                    await Task.Delay(100);
            }
            catch { /* ignora */ }
            finally { try { ws.Dispose(); } catch { } }
        }
    }
}
