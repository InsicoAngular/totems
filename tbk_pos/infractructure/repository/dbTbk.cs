using System.Data;
using Dapper;
using System.Data.SqlClient;
using tbk_pos.infractructure.dto;

namespace tbk_pos.infractructure.repository
{
    public class dbTbk
    {
        private readonly string _connectionString;     
        private readonly int _CajaId;
        private readonly int _CajeroId;
        private readonly int _BoletinId;

        public dbTbk(IConfiguration configuration)
        {
            _connectionString = configuration.GetConnectionString("DefaultConnection");
            _CajaId = configuration.GetValue<int>("Aplicacion:cajaId");
            _CajeroId = configuration.GetValue<int>("Aplicacion:cajeroId");
            _BoletinId = configuration.GetValue<int>("Aplicacion:boletinId");
        }

        public SqlConnection GetConnection()
        {
            return new SqlConnection(_connectionString);
        }


        public async Task<IEnumerable<dynamic>> GetDeudas(string irut, string idv)
        {
            const string query = @"
        SELECT
            TE.TEGiroId,
            TE.Folio,
            TE.Identificacion,
            PP.PAPersonaId,
            PP.RutNumero,
            PP.RutDigito,
            CONCAT(PP.Nombres, ' ', PP.ApellidoPaterno, ' ', PP.ApellidoMaterno) AS Nombres,
            ISNULL(
                (
                    SELECT TOP 1 PD.Direccion
                    FROM PADireccion PD
                    WHERE PD.PAPersonaId = PP.PAPersonaId
                          AND LEN(PD.Direccion) > 0
                          AND PD.Principal = 1
                ),
                'SIN DIRECCION'
            ) AS Direccion,
            TE.Monto,
            TE.Reajuste,
            TE.Intereses,
            TE.Total,
            TE.Glosa,
            TB.Descripcion AS Boletin,
            TE.FechaVencimiento,
            CAST(0 AS BIT) AS Pago,
            PC.Descripcion AS CCosto,
            TE.TEBoletinId,
            TE.TEPagoId,

            -- Lo que de verdad necesitas de ALCEstados:
            AEST.FolioTesoreria,
            AEST.FechaPago

        FROM TEGiro TE
        JOIN PAPersona PP  
            ON TE.PAPersonaId = PP.PAPersonaId
        JOIN TEBoletin TB  
            ON TE.TEBoletinId = TB.TETipoBoletinId

        -- Si requieres la info de DVGiro/PACCosto (centro de costo), lo conservas:
        LEFT JOIN DVGiro DG  
            ON TE.Folio = DG.Folio
        LEFT JOIN PACCosto PC  
            ON COALESCE(DG.PACCostoId, TE.PACCostoId) = PC.PACCostoId 

        -- Unión para licencias (boletín 20) en ALCEstados
        LEFT JOIN ALCEstados AEST 
            ON TE.Folio = AEST.FolioTesoreria 
               AND TE.TEBoletinId = 20

        -- Ya NO unimos TELicencia, pues no la necesitas:
        -- LEFT JOIN TELicencia TL
        --     ON TE.Folio = TL.Folio 
        --        AND TE.TEBoletinId IN (98,21)

        WHERE 
            TE.TEBoletinId IN (98, 20, 21)            
            AND TE.TEPagoId IS NULL
            AND TE.FechaAnulacion IS NULL
            AND TE.Convenio = 0

            -- Para boletín 20, si existe registro en ALCEstados, exigimos que FechaPago sea NULL;
            -- si no existe registro (todo AEST.* = NULL), también te lo trae.  
            AND (
                 TE.TEBoletinId <> 20
                 OR AEST.FechaPago IS NULL
            )

            -- Filtrado por centro de costo, si corresponde, según tu lógica anterior:
            AND (
                   (TE.TEBoletinId = 98       AND PC.PACCostoId IN (350,12,50,180,9,49,213))
                OR (TE.TEBoletinId IN (20,21) AND PC.PACCostoId IN (69,238,239,528,529,530))
            )

            AND NOT EXISTS (
                SELECT 1
                FROM TEGiro TE2
                WHERE TE2.Folio = TE.Folio
                      AND TE2.TEPagoId IS NOT NULL
            )

            AND PP.RutNumero = @irut
            AND PP.RutDigito = @idv

        ORDER BY TE.FechaVencimiento;
    ";

            using var connection = GetConnection();
            return await connection.QueryAsync<dynamic>(query, new { irut, idv });
        }


        public async Task<IEnumerable<dynamic>> GetDetallePago(int ifolio)
        {

            const string query = @"

SELECT
    te.TEGiroId,
    te.Folio,
    te.Identificacion,
    pp.PAPersonaId,
    pp.RutNumero,
    pp.RutDigito,
    CONCAT(pp.Nombres, ' ', pp.ApellidoPaterno, ' ', pp.ApellidoMaterno) AS Nombres,
    ISNULL((
        SELECT TOP 1 PD.Direccion
        FROM PADireccion PD
        WHERE PD.PAPersonaId = pp.PAPersonaId
          AND LEN(PD.Direccion) > 0
          AND PD.Principal = 1
    ), 'SIN DIRECCION') AS Direccion,
    te.Monto,
    te.Reajuste,
    te.Intereses,
    te.Total,
    te.Glosa,
    tb.Descripcion AS Boletin,
    te.FechaVencimiento,
    CAST(0 AS BIT) AS Pago,
    TTT.tbk_operacion,
    TTT.tbk_autorizacion,
    TTT.tbk_tarjeta,
    TTT.tbk_cuenta,
    TTT.folio,
    TTT.init_fecha
FROM TEGiro te
INNER JOIN TEBoletin tb ON te.TEBoletinId = tb.TETipoBoletinId
LEFT JOIN DVGiro dv ON te.Folio = dv.Folio
INNER JOIN PAPersona pp ON te.PAPersonaId = pp.PAPersonaId
INNER JOIN TEPAGO tp ON te.TEPagoId = tp.TEPagoId
INNER JOIN TO_Transaccion TTT 
    ON tp.TEPagoId = TTT.TEPagoId
INNER JOIN (
    SELECT LTRIM(RTRIM(value)) AS folio_individual
    FROM TO_Transaccion
    CROSS APPLY STRING_SPLIT(init_folios, ',')
    WHERE FOLIO = @ifolio
      AND tbk_codeStatus = 0
      AND TEPagoId IS NOT NULL
) AS initT ON te.Folio = initT.folio_individual
WHERE te.TEPagoId IS NOT NULL
ORDER BY te.FechaVencimiento;
";
            using var connection = GetConnection();
            return await connection.QueryAsync<dynamic>(query, new { ifolio });
        }
        public async Task<IEnumerable<dynamic>> GetMovimientos(
            DateTime fecha, int? rutNumero, string? rutDigito, string? folio, int? cajaId = null)
        {
            const string sql = @"
SELECT t.*, u.*, pa.*
FROM TO_Transaccion t
CROSS APPLY STRING_SPLIT(t.init_folios, ',') s
 INNER JOIN TEGiro u ON LTRIM(RTRIM(s.value)) = CAST(u.Folio AS NVARCHAR(50))
INNER JOIN PAPersona pa ON pa.PAPersonaId = u.PAPersonaId
WHERE CONVERT(date, t.init_fecha) = @fecha
  AND (t.TECajaId = @cajaId OR t.TECajaId IS NULL)
  AND (@rutNumero IS NULL OR @rutNumero = '' OR pa.RutNumero = @rutNumero)
  AND (@rutDigito IS NULL OR @rutDigito = '' OR pa.RutDigito = @rutDigito)
  AND (@folio IS NULL OR @folio = '' OR u.Folio = @folio)
ORDER BY t.init_fecha DESC;
";

            using var cn = GetConnection();
            var result = await cn.QueryAsync<dynamic>(sql, new
            {
                fecha = fecha.Date,
                rutNumero = rutNumero?.ToString(),
                rutDigito,
                folio,
                cajaId
            });
            // LOG para debugging:
            foreach (var r in result)
            {
                Console.WriteLine("Folio: " + r.Folio + " - Boletin: " + r.TEBoletinId);
            }
            return result;
        }



        public async Task<int> InsertTransaccionAsync(IEnumerable<dynamic> detalle)
        {
            // Cálculos de montos
            var canfolios = detalle.Count();
            var montototal = detalle.Sum(d => (decimal)d.Monto);
            var reajuste = detalle.Sum(d => (decimal)d.Reajuste);
            var interes = detalle.Sum(d => (decimal)d.Intereses);
            var total = detalle.Sum(d => (decimal)d.Total);
            var folios = string.Join(",", detalle.Select(d => d.Folio));

            const string sql = @"
    INSERT INTO TO_Transaccion 
    (init_fecha, init_folios, init_monto, init_reajuste, init_interes, init_total, init_totalfolios, TECajaId)
    VALUES (GETDATE(), @folios, @montototal, @reajuste, @interes, @total, @canfolios, @TECajaId);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
";

            using var connection = GetConnection();
            var generatedId = await connection.ExecuteScalarAsync<int>(sql, new
            {
                folios,
                montototal,
                reajuste,
                interes,
                total,
                canfolios,
                TECajaId = _CajaId  // ← Tu config ya lo tiene como _CajaId, que es el valor INT de la caja
            });

            return generatedId;
        }

        public async Task<bool> UpdateTransaccionAsync(int folio, UpdateTransaccionDto updateData)
        {
            const string sqlUpdate = @"
                UPDATE TO_Transaccion
                SET 
                    tbk_codeStatus = @CodeStatus,
                    tbk_terminal   = @Terminal,
                    tbk_fecha      = @Fecha,
                    tbk_hora       = @Hora,
                    tbk_tarjeta    = @Tarjeta,
                    tbk_cuenta     = @Cuenta,
                    tbk_marca      = @Marca,
                    tbk_autorizacion = @Autorizacion,
                    tbk_operacion    = @Operacion
                WHERE folio = @Folio
            ";

            using var connection = GetConnection();
            var rowsAffected = await connection.ExecuteAsync(sqlUpdate, new
            {
                CodeStatus = updateData.CodeStatus,
                Terminal = updateData.Terminal,
                Fecha = updateData.Fecha,
                Hora = updateData.Hora,
                Tarjeta = updateData.Tarjeta,
                Cuenta = updateData.Cuenta,
                Marca = updateData.Marca,
                Autorizacion = updateData.Autorizacion,
                Operacion = updateData.Operacion,
                Folio = folio
            });

            // Ejecuta procedimiento almacenado para ejecutar proceso de pago
            const string sqlPago = @"EXEC DBO.TO_PagosTotem @Folio,@CajaId,@CajeroId,@BoletinId";
            var rowsAffected2 = await connection.ExecuteAsync(sqlPago, new
            {
                Folio = folio,
                CajaId = _CajaId,
                CajeroId = _CajeroId,
                BoletinId = _BoletinId
            });

            return rowsAffected > 0;
        }

        public async Task InsertLogAsync(string folio, string mensaje)
        {
            using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync();

            const string sql = @"
                INSERT INTO TO_TransaccionLog (Folio, Mensaje, FechaCreacion)
                VALUES (@Folio, @Mensaje, GETDATE())
            ";

            using var cmd = new SqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@Folio", (object)folio ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Mensaje", (object)mensaje ?? DBNull.Value);

            await cmd.ExecuteNonQueryAsync();
        }
    }
}
