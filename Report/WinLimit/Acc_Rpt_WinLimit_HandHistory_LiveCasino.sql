USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_WinLimit_HandHistory_LiveCasino]
	@CustID INT,
	@ReachedDate DATETIME,
	@BetType INT
AS
/*
	Created:	Harper@20161013
	Task:		#61220: Generate data for HandHistory tab of Email Template Phase 3
	DB:			DBACC.bodb02

	Revisions:

	Param's Explanation:
		@CustID: Customer that reach Win Limit
		@ReachedDate: date that user reach win limit

	EXEC Acc_Rpt_WinLimit_HandHistory_LiveCasino @CustID = 23946479, @ReachedDate = '20161128', @Bettype = 1103
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @ShortReachedDate DATE = CONVERT(VARCHAR(10), @ReachedDate, 111)	

	DECLARE @TmpLiveCasino TABLE
	(	
		Transid			INT,
		Bettype			SMALLINT,
		GameCode		NVARCHAR(50),
		Brand			VARCHAR(5),
		Game			VARCHAR(50),
		GameType		NVARCHAR(50),
		GameGroup		NVARCHAR(1000),
		Betteam			NVARCHAR(50),
		BetDate			DATETIME,
		GameDate		DATETIME,
		TimeDiff		TIME,
		GameDuration	TIME,
		TotalBet		MONEY,
		PlayerWL		MONEY,
		GameIncome		MONEY,
		CompanyTurnOver MONEY,
		CompanyComm		MONEY,
		CompanyNetIncome MONEY,
		Betstatus		NVARCHAR(100),
		Eventstatus		NVARCHAR(100),
		Finalhomescore  INT,
		H				MONEY,
		S				MONEY,
		M				MONEY,
		A				MONEY
	)

	-- Get sport bettype
	-- Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)
	
	DECLARE @SportBettype TABLE (ProductID INT, Bettype INT)

	INSERT INTO @SportBettype (ProductID, Bettype)
	SELECT ProductID, Bettype 
	FROM dbo.f_SportBettypeMatrix_Sel (0, 0, 0, 2, '', '', @isTest)	
	WHERE ProductID = 4 --Live Casino

	INSERT INTO @TmpLiveCasino	        
	SELECT
		bg.transid
		, bg.bettype	
		, m.matchcode		AS GameCode
		, 'SLI'				AS Brand
		, 'Live Casino'		AS Game
		, ''				AS GameType
		, l.leaguename		AS GameGroup
		, bg.betteam		AS Betteam
		, bg.transdate		AS BetDate
		, m.kickofftime		AS GameDate
		, ''				AS TimeDiff 
		, CONVERT(TIME, (m.settletime - m.kickofftime)) AS GameDuration
		, bg.stake			AS TotalBet
		, (bg.winlost - bg.stake)	AS PlayerWL
		, (bg.stake - bg.winlost)	AS GameInCome 
		, (1 - bg.tpositiontaking) * bg.stake			AS CompanyTurnOver
		, bg.scomm					AS CompanyComm
		, ((bg.stake - bg.winlost) * (1 - bg.tpositiontaking)) - bg.scomm AS CompanyNetIncome 
		, m.betstatus
		, m.eventstatus
		, m.finalhomescore	
		, (1 - bg.tpositiontaking)	AS H
		, bg.spositiontaking		AS S
		, bg.mpositiontaking		AS M
		, bg.apositiontaking		AS A
	FROM dbo.bettransG bg (NOLOCK)
		INNER JOIN dbo.match m (NOLOCK) ON bg.matchid = m.matchid
		INNER JOIN @SportBettype s ON s.Bettype = bg.bettype		
		INNER JOIN dbo.League l (NOLOCK) ON m.leagueid = l.leagueid
	WHERE bg.statusID NOT IN (0, 1, 101, 102, 103) -- running, void, reject, refund
		AND bg.custid = @CustID AND CONVERT(VARCHAR(10), bg.winlostdate, 111) = @ShortReachedDate 
		AND bg.bettype = @BetType

	-- Update Time Difference
	UPDATE T
	SET T.TimeDiff = CONVERT(TIME, R.TimeDiff)
	FROM
	(
		SELECT B.Transid, (B.GameDate - A.GameDate) AS TimeDiff
		FROM @TmpLiveCasino A CROSS JOIN @TmpLiveCasino B
		WHERE B.Transid IN (SELECT MIN (C.Transid) FROM @TmpLiveCasino C WHERE C.Transid > A.Transid)		
	) AS R INNER JOIN @TmpLiveCasino T ON R.Transid = T.Transid		

	--Update GameType
	UPDATE T
	SET T.GameType = b.typenamee
	FROM @TmpLiveCasino T INNER JOIN dbo.bettype b (NOLOCK) ON T.bettype = b.typeid

	SELECT GameCode,	
		Brand,
		Game,
		GameType,
		GameGroup,
		Betteam AS Bettype,
		BetDate,
		GameDate,
		TimeDiff,
		GameDuration,
		TotalBet,
		PlayerWL AS PlayerWinLoss,
		GameIncome,
		CompanyTurnOver,
		CompanyComm,
		CompanyNetIncome,
		Betstatus,
		Eventstatus,
		Finalhomescore,
		H,
		S,
		M,
		A	
	FROM @TmpLiveCasino
	ORDER BY GameCode

	SELECT t.GameCode, SUM(t.TotalBet) AS TotalBet, SUM(t.GameIncome) AS GameInCome, t.GameDuration
	FROM @TmpLiveCasino t
	GROUP BY t.GameCode, t.GameDuration
	ORDER BY t.GameCode

END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinLimit_HandHistory_LiveCasino] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinLimit_HandHistory_LiveCasino] TO [vnteam]
GO