
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
		   @tblProduct TABLE
						 (
		   CasinoType  INT, 
		   ProductId   INT, 
		   ProductName VARCHAR(50), 
		   TimeSetting VARCHAR(10)
						 );
	   DECLARE 
		   @tblProductBetting TABLE
							   (
		   ProductId INT
							   );

	   INSERT INTO @tblProduct
		 (
			CasinoType, 
			ProductId, 
			ProductName, 
			TimeSetting
		 )
			SELECT 
				  p.CasinoType, 
				  p.ProductID, 
				  p.ProductName, 
				  '10 Mins' TimeSetting
			FROM Products p WITH(NOLOCK)
			WHERE p.ProductName IN('AE Sexy', 'Allbet', 'Lottery', 'MaxGame', 'ON Casino', 'PG Soft', 'PP', 'PP Live Casino', 'RNG Keno', 'SA Gaming', 'SABA.games', 'Table Game', 'Vgaming', 'Virtual Sports', 'Virtual Sports 2', 'WE Live Casino')
			UNION ALL
			SELECT 
				  p.CasinoType, 
				  p.ProductID, 
				  p.ProductName, 
				  '30 Mins' TimeSetting
			FROM Products p WITH(NOLOCK)
			WHERE p.ProductName IN('Arcadia Gaming', 'ASKMESLOT', 'BG', 'FA CHAI', 'FastSpin', 'GPI', 'GPI Live Casino', 'Habanero', 'IBCBet Live Casino', 'Jili', 'Macau Games', 'MG-RNG', 'Nextspin', 'PLAYSTAR', 'Playtech', 'Saba Casino', 'SG', 'YeeBet')
			UNION ALL
			SELECT 
				  p.CasinoType, 
				  p.ProductID, 
				  p.ProductName, 
				  '60 Mins' TimeSetting
			FROM Products p WITH(NOLOCK)
			WHERE p.ProductName IN('BBIN', 'AdvantPlay', 'CG', 'FGG', 'Funky Games', 'ION', 'Joker', 'Number Game', 'Live22', 'SABA xD', 'SEAL Entertainment', 'Sports Lottery', 'UU SLOTS', 'Virtual Games', 'Virtual Sports 3', 'Virtual Sports 4', 'Virtual Sports 5', 'WM')
			ORDER BY 
				    p.CasinoType DESC;

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
			UNION ALL
			SELECT DISTINCT 
				  sb.ProductID
			FROM SportBettypeMatrix sb WITH(NOLOCK)
				INNER JOIN bettransLC b WITH(NOLOCK) ON sb.BetType = b.gameID
				INNER JOIN @tblProduct p ON p.ProductId = sb.ProductID
			WHERE b.transdate BETWEEN @StartDate AND @EndDate
			UNION ALL
			SELECT DISTINCT 
				  sb.ProductID
			FROM SportBettypeMatrix sb WITH(NOLOCK)
				INNER JOIN bettransRNG b WITH(NOLOCK) ON sb.BetType = b.gameID
				INNER JOIN @tblProduct p ON p.ProductId = sb.ProductID
			WHERE b.transdate BETWEEN @StartDate AND @EndDate;

	   SELECT DISTINCT 
			p1.ProductName, 
			p1.TimeSetting
	   FROM @tblProduct p1
		   LEFT JOIN @tblProductBetting p2 ON p1.ProductId = p2.ProductId
	   WHERE ISNULL(p2.ProductId, 0) = 0
	   ORDER BY 
			  p1.TimeSetting;
    END;
GO
