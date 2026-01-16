GO
/****** Object:  StoredProcedure [dbo].[sp_LlamarTotem]    Script Date: 31-07-2025 11:46:19 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER   PROCEDURE [dbo].[sp_LlamarTotem]
    @RutNumero     int,
    @RutDigito     char(1),
    @Nombre        nvarchar(250),
    @Modulo        int,
    @TipoEspera    char(1) = 'S'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @today char(8) = CONVERT(char(8), GETDATE(), 112);
	DECLARE @hour  CHAR(6) = FORMAT(GETDATE(), 'HHmmss');

    /* Padre */
    INSERT INTO dbo.ALCLLAMADOS
           (Fecha, Hora, Tipo_Espera, RutNumero, RutDigito,
            id_terminal, id_atencion, Correlativo, NombreCompleto)
    VALUES (@today, @hour, @TipoEspera,
            @RutNumero, @RutDigito,
            13, 0, 0, @Nombre);

    DECLARE @id int = SCOPE_IDENTITY();

    /* Hijo */
    INSERT INTO dbo.ALCLLAMADOSTOTEM (fecha, hora, id_llamados, modulo)
    VALUES (@today, @hour, @id, @Modulo);
END
