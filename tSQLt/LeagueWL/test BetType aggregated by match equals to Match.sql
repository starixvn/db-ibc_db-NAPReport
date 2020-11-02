USE bodb02
GO

ALTER PROCEDURE testLeagueWinloss.[test BetType aggregated by match equals to Match]
AS
	/*created by Jaden: check if aggregated numbers of BetType report (3rd) matches number of Match report (2nd)
						in a single match*/
	/*execution: `tSQLt.Run 'testLeagueWinloss.[test BetType aggregated by match equals to Match]'`*/
BEGIN
    -------------------------------------------------------------
    IF OBJECT_ID('tempdb..#actual') IS NOT NULL DROP TABLE #actual
    IF OBJECT_ID('tempdb..#actual_live0') IS NOT NULL DROP TABLE #actual_live0
    IF OBJECT_ID('tempdb..#actual_live1') IS NOT NULL DROP TABLE #actual_live1
    IF OBJECT_ID('tempdb..#expected') IS NOT NULL DROP TABLE #expected
    -------------------------------------------------------------
    EXEC dbo.[__set up tests__]
    -------------------------------------------------------------
	DECLARE @ReportDateTestInput   DATE
	DECLARE @SportBetTypeTestInput VARCHAR(MAX)
	DECLARE @IsNoDrawTestInput	   BIT
	DECLARE @SiteNameTestInput 	   VARCHAR(MAX)
	DECLARE @LeagueNameTestInput   VARCHAR(MAX)
    DECLARE @MatchIDTestInput      INT
    -------------------------------------------------------------
	CREATE TABLE #actual ( MatchID              INT,
                           LiveIndicator        BIT,
                           MemberWinLoss		MONEY,
						   SMAWinLoss			MONEY,
						   ExtraPT				MONEY,
						   Commission			MONEY,
						   RealIncome			MONEY,
						   VirtualIncome		MONEY,
						   VarianceIncome		MONEY,
						   RealTurnover		    MONEY,
						   VirtualTurnover		MONEY)

	CREATE TABLE #expected(MatchID              INT,
                           LiveIndicator        BIT,
                           MemberWinLoss		MONEY,
						   SMAWinLoss			MONEY,
						   ExtraPT				MONEY,
						   Commission			MONEY,
						   RealIncome			MONEY,
						   VirtualIncome		MONEY,
						   VarianceIncome		MONEY,
						   RealTurnover		    MONEY,
						   VirtualTurnover		MONEY)
    -------------------------------------------------------------
	EXEC testLeagueWinloss.[retrieve test parameters] 
		  @ReportDate   = @ReportDateTestInput 		OUTPUT
		, @SportBetType = @SportBetTypeTestInput 	OUTPUT
		, @IsNoDraw     = @IsNoDrawTestInput 		OUTPUT
		, @SiteName		= @SiteNameTestInput 		OUTPUT
		, @LeagueName	= @LeagueNameTestInput		OUTPUT
        , @MatchID      = @MatchIDTestInput         OUTPUT
    ------------build #actual
   	EXEC testLeagueWinloss.[report by match from LeagueWL_Match]
			  @ReportDateT 		= @ReportDateTestInput
			, @SportBettypeT	= @SportBetTypeTestInput
			, @IsNoDrawT		= @IsNoDrawTestInput
			, @SiteNameT		= @SiteNameTestInput 
            , @LeagueNameT		= @LeagueNameTestInput
            , @MatchIDT         = @MatchIDTestInput
    ------------build #expected
    BEGIN
        EXEC testLeagueWinloss.[report by match from LeagueWL_BetType]
                @ReportDateT 		= @ReportDateTestInput
                , @SportBettypeT	= @SportBetTypeTestInput
                , @IsNoDrawT		= @IsNoDrawTestInput
                , @SiteNameT		= @SiteNameTestInput
                , @MatchIDT		    = @MatchIDTestInput
                , @LiveIndicatorT   = 0

        SELECT * INTO #actual_live0 FROM #actual WHERE LiveIndicator = 0
        -------------------------------------------------------------
        EXEC tSQLt.AssertEqualsTable '#expected', '#actual_live0';
        -------------------------------------------------------------
        TRUNCATE TABLE #expected
    END
    BEGIN
        EXEC testLeagueWinloss.[report by match from LeagueWL_BetType]
                @ReportDateT 		= @ReportDateTestInput
                , @SportBettypeT	= @SportBetTypeTestInput
                , @IsNoDrawT		= @IsNoDrawTestInput
                , @SiteNameT		= @SiteNameTestInput
                , @MatchIDT		    = @MatchIDTestInput
                , @LiveIndicatorT   = 1

        SELECT * INTO #actual_live1 FROM #actual WHERE LiveIndicator = 1
        -------------------------------------------------------------
        EXEC tSQLt.AssertEqualsTable '#expected', '#actual_live1';
        -------------------------------------------------------------
        TRUNCATE TABLE #expected
    END

END;
GO

ALTER PROCEDURE testLeagueWinloss.[report by match from LeagueWL_Match]
    @ReportDateT   DATE,
    @SportBetTypeT VARCHAR(MAX),
    @IsNoDrawT     BIT,
    @SiteNameT     VARCHAR(MAX),
    @LeagueNameT   VARCHAR(MAX),
    @MatchIDT      INT
AS
BEGIN
    ------------------------------------------------------------
    IF OBJECT_ID('tempdb..#result') IS NOT NULL DROP TABLE #result;
	CREATE TABLE #result ( MatchID				INT,
						   MatchEvent           NVARCHAR(100),
						   IsHedge              BIT,
						   LiveIndicator		BIT,
						   MemberWinLoss		MONEY,
						   SMAWinLoss			MONEY,
						   ExtraPT				MONEY,
						   Commission			MONEY,
						   RealIncome			MONEY,
						   VirtualIncome		MONEY,
						   VarianceIncome		MONEY,
						   RealTurnover		    MONEY,
						   VirtualTurnover		MONEY)
    ------------------------------------------------------------
	INSERT INTO #result
        EXEC dbo.Acc_Rpt_LeagueWL_Match_xtest 
                  @StartDate  	= @ReportDateT
                , @EndDate		= @ReportDateT
                , @SportBettype = @SportBettypeT
                , @IsNoDraw		= @IsNoDrawT
                , @SiteName     = @SiteNameT
                , @LeagueName   = @LeagueNameT
    ------------------------------------------------------------
    INSERT INTO #actual
    SELECT  @MatchIDT,
            LiveIndicator,
            SUM(MemberWinLoss)		MemberWinLoss,
            SUM(SMAWinLoss)			SMAWinLoss,
            SUM(-ExtraPT)			ExtraPT,
            SUM(Commission)			Commission,
            SUM(RealIncome)			RealIncome,
            SUM(VirtualIncome)		VirtualIncome,
            SUM(VarianceIncome)		VarianceIncome,
            SUM(RealTurnover)		RealTurnover,
            SUM(VirtualTurnover)	VirtualTurnover
    FROM #result
    WHERE MatchID = @MatchIDT
    GROUP BY LiveIndicator
    ------------------------------------------------------------
    DROP TABLE #result
    ------------------------------------------------------------
END
GO

ALTER PROCEDURE testLeagueWinloss.[report by match from LeagueWL_BetType] 
    @ReportDateT    DATE,
    @SportBetTypeT  VARCHAR(MAX),
    @IsNoDrawT      BIT,
    @SiteNameT      VARCHAR(MAX),
    @MatchIDT       INT,
    @LiveIndicatorT BIT
AS
BEGIN
    IF @MatchIDT IS NULL 
        EXEC tSQLt.Fail '@MatchIDT should not be NULL'
    ------------------------------------------------------------
    IF OBJECT_ID('tempdb..#result') IS NOT NULL DROP TABLE #result;
	CREATE TABLE #result (BetType			INT,
						  BetTypeName		NVARCHAR(200),
						  SiteType			VARCHAR(20),
						  MemberWinLoss	    MONEY,
						  SMAWinLoss		MONEY,
						  ExtraPT			MONEY,
						  Commission		MONEY,
						  RealIncome		MONEY,
						  VirtualIncome 	MONEY,
						  VarianceIncome	MONEY,
						  RealTurnover		MONEY,
						  VirtualTurnover	MONEY)
    ------------------------------------------------------------
    INSERT INTO #result
        EXEC dbo.Acc_Rpt_LeagueWL_Bettype_xtest 
                  @StartDate  	 = @ReportDateT
                , @EndDate		 = @ReportDateT
                , @SportBettype  = @SportBettypeT
                , @IsNoDraw		 = @IsNoDrawT
                , @SiteName      = @SiteNameT
                , @LiveIndicator = @LiveIndicatorT
                , @MatchID       = @MatchIDT
    ------------------------------------------------------------
    INSERT INTO #expected
    SELECT  @MatchIDT,
            @LiveIndicatorT         LiveIndicator,
            SUM(MemberWinLoss)		MemberWinLoss,
            SUM(SMAWinLoss)			SMAWinLoss,
            SUM(-ExtraPT)			ExtraPT,
            SUM(Commission)			Commission,
            SUM(RealIncome)			RealIncome,
            SUM(VirtualIncome)		VirtualIncome,
            SUM(VarianceIncome)		VarianceIncome,
            SUM(RealTurnover)		RealTurnover,
            SUM(VirtualTurnover)	VirtualTurnover
    FROM #result
    ------------------------------------------------------------
    DROP TABLE #result
    ------------------------------------------------------------
END
GO