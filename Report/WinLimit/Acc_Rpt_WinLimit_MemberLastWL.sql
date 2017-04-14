USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_WinLimit_MemberLastWL]
	@ReachedDate	DATETIME,
	@ProductID		VARCHAR(MAX) = '',
	@Username		VARCHAR(MAX) = ''
AS
/*
	Created:	Harper@20161025
	Task:		#61220: Generate data for Section 3 - Member Last Win/Loss
	DB:			DBACC.bodb02

	Revisions:

	Param's Explanation:	
	
	EXEC Acc_Rpt_WinLimit_MemberLastWL '20161024', 4, 'C9888HH22'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @ShortReachedDate DATE = CONVERT(VARCHAR(10), @ReachedDate, 111)	
	DECLARE @SportBettype TABLE (ProductID INT, Bettype INT, BettypeName VARCHAR(50))
	DECLARE @TmpCust TABLE (CustID INT, UserName VARCHAR(50))
	
	-- Get Sport Bettype
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)	

	IF @ProductID <> ''
	BEGIN
		INSERT INTO @SportBettype (ProductID, Bettype)
		SELECT ProductID, Bettype 
		FROM [dbo].strSplit(@ProductID, ',') f
			INNER JOIN dbo.f_SportBettypeMatrix_Sel (0, 0, 0, 2, '', '', @isTest) s ON f.val = s.ProductID	

		UPDATE p
		SET p.BettypeName = b.typenamee
		FROM @SportBettype p
			LEFT JOIN bettype b (NOLOCK) ON p.Bettype = b.typeid	
	END	
	-- End

	-- Get User Name
	IF @Username <> ''
	BEGIN
		INSERT INTO @TmpCust (CustID, UserName)
		SELECT DISTINCT c.CustID, c.username
		FROM [dbo].strSplit(@UserName, ',') f
			INNER JOIN dbo.customer c (NOLOCK) ON c.username = f.val 
		WHERE c.roleid = 1
	END
	-- End
	
	SELECT b.custid
		, c.UserName
		, b.winlostdate			AS WinLossDate
		, s.BettypeName			AS Bettype
		, b.CurrencyName		AS Currency
		
		, COUNT(b.transid)		AS BetCount
		, SUM(b.actual_stake)	AS TotalBets
		, SUM(b.actual_stake - b.winlost) AS GameIncome
		, CASE 
			WHEN SUM(b.actual_stake) <= 0 THEN 0 
			ELSE SUM(b.winlost) * 100 / SUM(b.actual_stake)
			END	AS GamePayout
		, SUM((1 - b.tpositiontaking) * b.stake) AS CompanyTurnOver
		, SUM(b.winlost - b.actual_stake + b.awinlost + b.mwinlost + b.swinlost + b.scomm) AS CompanyNetIncome		

		, SUM(b.actual_stake * b.actualrate)	AS TotalBetsRM
		, SUM((b.actual_stake - b.winlost) * b.actualrate) AS GameIncomeRM
		, SUM((1 - b.tpositiontaking) * b.stake * b.actualrate) AS CompanyTurnOverRM
		, SUM((b.winlost - b.actual_stake + b.awinlost + b.mwinlost + b.swinlost + b.scomm) * b.actualrate) AS CompanyNetIncomeRM
		
		, SUM(b.scomm) AS CompanyComm
		, SUM(b.scomm * b.actualrate) AS CompanyCommRM
	FROM dbo.bettrans b (NOLOCK)
		INNER JOIN @SportBettype s ON s.Bettype = b.bettype
		INNER JOIN @TmpCust c ON b.custid = c.CustID
	WHERE b.statusID NOT IN (0, 1, 101, 102, 103) -- running, void, reject, refund				
		AND CONVERT(VARCHAR(10), b.winlostdate, 111) = @ShortReachedDate 
	GROUP BY b.CustID, 
			  c.UserName,
			  b.winlostdate,	
			  s.BettypeName,		  
			  b.CurrencyName
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinLimit_MemberLastWL] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinLimit_MemberLastWL] TO [vnteam]
GO
