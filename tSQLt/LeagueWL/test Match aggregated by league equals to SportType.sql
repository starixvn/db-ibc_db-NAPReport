USE bodb02
GO

ALTER PROCEDURE testLeagueWinloss.[test Match aggregated by league equals to SportType]
AS
	/*created by Jaden: check if aggregated numbers of Match report (2nd) matches number of SportType report (1st)
						in a single league*/
	/*execution: `tSQLt.Run 'testLeagueWinloss.[test Match aggregated equals to SportType]'`*/
BEGIN
	-------------------------------------------------------------
    IF OBJECT_ID('tempdb..#actual') IS NOT NULL DROP TABLE #actual
    IF OBJECT_ID('tempdb..#expected') IS NOT NULL DROP TABLE #expected
    -------------------------------------------------------------
    EXEC dbo.[__set up tests__]
    -------------------------------------------------------------
	DECLARE @ReportDateTestInput   DATE
	DECLARE @SportBetTypeTestInput VARCHAR(MAX)
	DECLARE @IsNoDrawTestInput	   BIT
	DECLARE @SiteNameTestInput 	   VARCHAR(MAX)
	DECLARE @LeagueNameTestInput   VARCHAR(MAX)
	-------------------------------------------------------------
	CREATE TABLE #actual ( SportType		INT,
						   Sport			NVARCHAR(100),
						   LeagueName		VARCHAR(150),
						   MemberWinLoss	MONEY,
						   SMAWinLoss		MONEY,
						   ExtraPT			MONEY,
						   Commission		MONEY,
						   RealIncome		MONEY,
						   VirtualIncome	MONEY,
						   VarianceIncome	MONEY,
						   RealTurnover		MONEY,
						   VirtualTurnover	MONEY)

	CREATE TABLE #expected(SportType		INT,
						   Sport			NVARCHAR(100),
						   LeagueName		VARCHAR(150),
						   MemberWinLoss	MONEY,
						   SMAWinLoss		MONEY,
						   ExtraPT			MONEY,
						   Commission		MONEY,
						   RealIncome		MONEY,
						   VirtualIncome	MONEY,
						   VarianceIncome	MONEY,
						   RealTurnover		MONEY,
						   VirtualTurnover	MONEY)
	-------------------------------------------------------------
	EXEC testLeagueWinloss.[retrieve test parameters] 
		  @ReportDate   = @ReportDateTestInput 		OUTPUT
		, @SportBetType = @SportBetTypeTestInput 	OUTPUT
		, @IsNoDraw     = @IsNoDrawTestInput 		OUTPUT
		, @SiteName		= @SiteNameTestInput 		OUTPUT
		, @LeagueName	= @LeagueNameTestInput		OUTPUT
-------------------------------------------------------------	
	EXEC testLeagueWinloss.[report by league from LeagueWL_SportType]
			  @ReportDateT 		= @ReportDateTestInput
			, @SportBettypeT	= @SportBetTypeTestInput
			, @IsNoDrawT		= @IsNoDrawTestInput
			, @SiteNameT		= @SiteNameTestInput
			, @LeagueNameT		= @LeagueNameTestInput

	EXEC testLeagueWinloss.[report by league from LeagueWL_Match]
			  @ReportDateT 		= @ReportDateTestInput
			, @SportBettypeT	= @SportBetTypeTestInput
			, @IsNoDrawT		= @IsNoDrawTestInput
			, @SiteNameT		= @SiteNameTestInput
			, @LeagueNameT		= @LeagueNameTestInput
	
	-------------------------------------------------------------
	EXEC tSQLt.AssertEqualsTable '#expected', '#actual';
	-------------------------------------------------------------
END;
GO

ALTER PROCEDURE testLeagueWinloss.[report by league from LeagueWL_SportType] 
    @ReportDateT   DATE,
    @SportBetTypeT VARCHAR(MAX),
    @IsNoDrawT     BIT,
    @SiteNameT     VARCHAR(MAX),
    @LeagueNameT   VARCHAR(MAX)
AS
BEGIN
    IF @LeagueNameT IS NULL
        EXEC tSQLt.Fail '@LeagueNameT should not be NULL'
    ------------------------------------------------------------
	INSERT INTO #actual
		EXEC dbo.Acc_Rpt_LeagueWL_Sporttype_xtest
				  @StartDate 	= @ReportDateT
				, @EndDate		= @ReportDateT
				, @SportBettype	= @SportBettypeT
				, @IsNoDraw		= @IsNoDrawT
                , @SiteName     = @SiteNameT
                , @LeagueName   = @LeagueNameT
	-- Can't test Parlay because Acc_Rpt_LeagueWL_Match does not include Parlay data
	DELETE FROM #actual WHERE Sport IN ('Parlay', 'SB Adjustment')
    ------------------------------------------------------------
END
GO

ALTER PROCEDURE testLeagueWinloss.[report by league from LeagueWL_Match] 
    @ReportDateT   DATE,
    @SportBetTypeT VARCHAR(MAX),
    @IsNoDrawT     BIT,
    @SiteNameT     VARCHAR(MAX),
    @LeagueNameT   VARCHAR(MAX)
AS
BEGIN
    IF @LeagueNameT IS NULL 
        EXEC tSQLt.Fail '@LeagueNameT should not be NULL'
    ------------------------------------------------------------
    IF OBJECT_ID('tempdb..#matchResult') IS NOT NULL DROP TABLE #matchResult;
	CREATE TABLE #matchResult (MatchID			INT,
							   MatchEvent		NVARCHAR(200),
							   IsHedge			BIT,
							   LiveIndicator	BIT,
							   MemberWinLoss	MONEY,
							   SMAWinLoss		MONEY,
							   ExtraPT			MONEY,
							   Commission		MONEY,
							   RealIncome		MONEY,
							   VirtualIncome	MONEY,
							   VarianceIncome	MONEY,
							   RealTurnover		MONEY,
							   VirtualTurnover	MONEY)
    ------------------------------------------------------------
    INSERT INTO #matchResult
        EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Match_xtest
                  @StartDate  	= @ReportDateT
                , @EndDate		= @ReportDateT
                , @SportBettype = @SportBettypeT
                , @IsNoDraw		= @IsNoDrawT
                , @SiteName     = @SiteNameT
                , @LeagueName   = @LeagueNameT
    ------------------------------------------------------------
    INSERT INTO #expected
    SELECT  m.SportType,
            MAX(SportName) 			Sport,
            LeagueName,
            SUM(MemberWinLoss)		MemberWinLoss,
            SUM(SMAWinLoss)			SMAWinLoss,
            SUM(-ExtraPT)			ExtraPT,
            SUM(Commission)			Commission,
            SUM(RealIncome)			RealIncome,
            SUM(VirtualIncome)		VirtualIncome,
            SUM(VarianceIncome)		VarianceIncome,
            SUM(RealTurnover)		RealTurnover,
            SUM(VirtualTurnover)	VirtualTurnover
        FROM #matchResult t
        INNER JOIN dbo.match m WITH (NOLOCK)
            ON m.matchid = t.MatchID
        INNER JOIN dbo.Sports s WITH (NOLOCK)
            ON s.SportType = m.sporttype
        INNER JOIN dbo.league l WITH (NOLOCK)
            ON m.sporttype = l.sporttype
            AND m.leagueid = l.leagueid
        GROUP BY m.SportType, LeagueName
    ------------------------------------------------------------
    DROP TABLE #matchResult
    ------------------------------------------------------------
END
GO