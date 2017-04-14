
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  User Defined Function dbo.Lrf_f_basecurrency    Script Date: 3/12/2015 10:28:54 AM ******/


CREATE FUNCTION [dbo].[Lrf_f_basecurrency]
	( @Date  DATETIME
	)
RETURNS @OutPutTable TABLE (ID TINYINT, Currency VARCHAR(3), isdefault TINYINT)	
AS 
/*  
 * Created by : [20150206@Jim]  
 * Task  :Add new base currency "GBP" for NAP reports (Feature #30110)
 * DB   : DBEXT.bodb02 /DBACC.bodb02 
*/
BEGIN
	INSERT INTO @OutPutTable(ID, Currency,isdefault)
		SELECT 1 ID , 'USD' Currency , 0 AS isdefault
		UNION ALL
		SELECT 2, 'MYR',0
		UNION ALL
		SELECT 3, 'EUR',0
		UNION ALL
		SELECT 4, 'GBP',1
	IF @Date < '2015-02-01'
		BEGIN
			UPDATE @OutPutTable
			SET isdefault = 0 
			WHERE ID = 4
			
			UPDATE @OutPutTable
			SET isdefault = 1 
			WHERE ID = 3
		END
	
	RETURN	
END

GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
