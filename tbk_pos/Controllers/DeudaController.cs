using Microsoft.AspNetCore.Mvc;
using tbk_pos.infractructure.dto;
using tbk_pos.infractructure.repository;

// For more information on enabling Web API for empty projects, visit https://go.microsoft.com/fwlink/?LinkID=397860

namespace tbk_pos.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class DeudaController : ControllerBase
    {

        private readonly dbTbk _dbTbk;


        public DeudaController( dbTbk dbTbk)
        {
            _dbTbk = dbTbk;
        }

        [HttpGet("{rut}")]
        public async Task<IActionResult> GetDeuda(string rut)
        {
            try
            {
                // Separar el RUT en número e identificación
                var rutParts = rut.Split("-");
                if (rutParts.Length != 2)
                {
                    return BadRequest(new { success = false, error = "Formato de RUT inválido" });
                }

                var irut = rutParts[0];
                var idv = rutParts[1];

                // Obtener los datos desde dbTbk
                var result = (await _dbTbk.GetDeudas(irut, idv)).ToList();

                // Verificar si hay resultados
                if (!result.Any())
                {
                    return NotFound(new { success = false, error = "No se encontró deuda para este RUT" });
                }

                // Preparar la respuesta
                var response = new
                {
                    success = true,
                    Rut = rut,
                    Nombre = result[0].Nombres,
                    Direccion = result[0].Direccion,
                    Tramite = result[0].Boletin,
                    Folio = 0,
                    Total_monto = result.Sum(r => (decimal)r.Monto),
                    Total_reajuste = result.Sum(r => (decimal)r.Reajuste),
                    Total_intereses = result.Sum(r => (decimal)r.Intereses),
                    Total_deudas = result.Sum(r => (decimal)r.Total),
                    Detalle = result
                };

                return Ok(response);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error al obtener la deuda: {ex.Message}");
                return StatusCode(500, new { success = false, error = "Error interno del servidor" });
            }
        }

        [HttpPost("insert")]
        public async Task<IActionResult> InsertTransaccion([FromBody] TransaccionDto data)
        {
            try
            {
                // Validar datos de entrada
                if (data.Detalle == null || !data.Detalle.Any())
                {
                    return BadRequest(new { success = false, error = "El detalle no puede estar vacío." });
                }

                // Insertar transacción en la base de datos
                var generatedId = await _dbTbk.InsertTransaccionAsync(data.Detalle);

                // Retornar respuesta exitosa
                return Ok(new
                {
                    success = true,
                    transaccionId = generatedId
                });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error al insertar la transacción: {ex.Message}");
                return StatusCode(500, new { success = false, error = "Error interno del servidor" });
            }
        }



        [HttpPut("update/{folio}")]
        public async Task<IActionResult> UpdateTransaccion(int folio, [FromBody] UpdateTransaccionDto updateData)
        {
            try
            {
                // Validar los datos de entrada
                if (updateData == null)
                {
                    return BadRequest(new { success = false, error = "Datos de actualización no válidos." });
                }

                var success = await _dbTbk.UpdateTransaccionAsync(folio, updateData);

                if (!success)
                {
                    return NotFound(new { success = false, error = "No se encontró la transacción con el folio especificado." });
                }

                return Ok(new { success = true, message = "Transacción actualizada exitosamente." });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error al actualizar la transacción: {ex.Message}");
                return StatusCode(500, new { success = false, error = "Error interno del servidor." });
            }
        }


    }
}
