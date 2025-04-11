
/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

/*
	Creator:	20250402@Robert
	Task: #222345 - Letstalk - No Bets Alert [ReportID 48]
	Database:	DBACC.bodb02 
	
	Revisions:
		- 20250402@Robert: #222345 - Letstalk - No Bets Alert [ReportID 48]		
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/

CREATE PROC [dbo].[Acc_Rpt_LetstalkNoBetsAlert] 
	@StartDate DATETIME, 
	@EndDate   DATETIME
AS
    BEGIN

	   DECLARE 
		   @WLDate DATE;
	   SELECT 
			@WLDate = CAST(@StartDate AS DATE);

	   DECLARE 
		   @tblProduct TABLE
						 (
		   ProductId   INT, 
		   TimeSetting VARCHAR(10)
						 );
	   DECLARE 
		   @tblProductBetting TABLE
							   (
		   ProductId INT
							   );

	   INSERT INTO @tblProduct
		 (
			ProductId, 
			TimeSetting
		 )
			SELECT 
				  5 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  8 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  21 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  27 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  28 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  32 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  39 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  40 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  42 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  45 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  55 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  60 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  65 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  66 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  80 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  96 ProductID, 
				  '10 Mins' TimeSetting
			UNION ALL
			SELECT 
				  6 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  22 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  34 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  36 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  46 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  48 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  57 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  61 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  73 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  75 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  76 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  85 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  87 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  89 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  90 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  91 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  100 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  103 ProductID, 
				  '30 Mins' TimeSetting
			UNION ALL
			SELECT 
				  3 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  38 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  47 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  51 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  52 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  56 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  62 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  63 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  67 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  70 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  72 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  77 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  78 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  79 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  83 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  86 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  88 ProductID, 
				  '60 Mins' TimeSetting
			UNION ALL
			SELECT 
				  104 ProductID, 
				  '60 Mins' TimeSetting;



	   INSERT INTO @tblProductBetting
		 (
			ProductId
		 )
			SELECT DISTINCT 
				  sb.ProductID
			FROM SportBettypeMatrix sb WITH(NOLOCK)
				INNER JOIN bettrans b WITH(NOLOCK) ON sb.BetType = b.bettype
				INNER JOIN @tblProduct p ON p.ProductId = sb.ProductID
			WHERE b.transdate BETWEEN @StartDate AND @EndDate
				 AND b.winlostdate = @WLDate
			UNION ALL
			SELECT DISTINCT 
				  sb.ProductID
			FROM SportBettypeMatrix sb WITH(NOLOCK)
				INNER JOIN bettransLC b WITH(NOLOCK) ON sb.BetType = b.gameID
				INNER JOIN @tblProduct p ON p.ProductId = sb.ProductID
			WHERE b.transdate BETWEEN @StartDate AND @EndDate
				 AND b.winlostdate = @WLDate
			UNION ALL
			SELECT DISTINCT 
				  sb.ProductID
			FROM SportBettypeMatrix sb WITH(NOLOCK)
				INNER JOIN bettransRNG b WITH(NOLOCK) ON sb.BetType = b.gameID
				INNER JOIN @tblProduct p ON p.ProductId = sb.ProductID
			WHERE b.transdate BETWEEN @StartDate AND @EndDate
				 AND b.winlostdate = @WLDate;

	   SELECT DISTINCT 
			p.ProductName, 
			p1.TimeSetting
	   FROM @tblProduct p1
		   INNER JOIN Products p WITH(NOLOCK) ON p1.ProductId = p.ProductID
		   LEFT JOIN @tblProductBetting p2 ON p1.ProductId = p2.ProductId
	   WHERE ISNULL(p2.ProductId, 0) = 0
	   ORDER BY 
			  p1.TimeSetting;
    END;
GO
