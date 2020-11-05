USE bodb02
GO

ALTER PROCEDURE testLeagueWinloss.[test Site aggregated by bettype equals to BetType]
AS
	/*execution: `tSQLt.Run 'testLeagueWinloss.[test Site aggregated by bettype equals to BetType]'`*/
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
    DECLARE @MatchIDTestInput      INT
    DECLARE @BetTypeTestInput      INT
    -------------------------------------------------------------
	CREATE TABLE #actual (MatchID           INT,
                          BetType			INT,
						  MemberWinLoss	    MONEY,
						  SMAWinLoss		MONEY,
						  ExtraPT			MONEY,
						  Commission		MONEY,
						  RealIncome		MONEY,
						  VirtualIncome 	MONEY,
						  VarianceIncome	MONEY,
						  RealTurnover		MONEY,
						  VirtualTurnover	MONEY)

	CREATE TABLE #expected(MatchID          INT,
                           BetType			INT,
                           MemberWinLoss	MONEY,
                           SMAWinLoss		MONEY,
                           ExtraPT			MONEY,
                           Commission		MONEY,
                           RealIncome		MONEY,
                           VirtualIncome 	MONEY,
                           VarianceIncome	MONEY,
                           RealTurnover		MONEY,
                           VirtualTurnover	MONEY)
    -------------------------------------------------------------
	EXEC testLeagueWinloss.[retrieve test parameters] 
		  @ReportDate   = @ReportDateTestInput 		OUTPUT
		, @SportBetType = @SportBetTypeTestInput 	OUTPUT
		, @IsNoDraw     = @IsNoDrawTestInput 		OUTPUT
		, @SiteName		= @SiteNameTestInput 		OUTPUT
        , @MatchID      = @MatchIDTestInput         OUTPUT
        , @BetType      = @BetTypeTestInput         OUTPUT
    ------------build #actual
   	EXEC testLeagueWinloss.[report by BetType from LeagueWL_BetType] 
			  @ReportDateT 		= @ReportDateTestInput
			, @SportBettypeT	= @SportBetTypeTestInput
			, @IsNoDrawT		= @IsNoDrawTestInput
			, @SiteNameT		= @SiteNameTestInput
            , @MatchIDT         = @MatchIDTestInput
            , @BetTypeT         = @BetTypeTestInput

    ------------build #expected
    EXEC testLeagueWinloss.[report by BetType from LeagueWL_Site] 
            @ReportDateT 		= @ReportDateTestInput
            , @IsNoDrawT		= @IsNoDrawTestInput
            , @SiteNameT		= @SiteNameTestInput
            , @MatchIDT		    = @MatchIDTestInput
            , @BetTypeT         = @BetTypeTestInput

    -------------------------------------------------------------
    EXEC tSQLt.AssertEqualsTable '#expected', '#actual';
    -------------------------------------------------------------
END;
GO

ALTER PROCEDURE testLeagueWinloss.[report by BetType from LeagueWL_BetType] 
    @ReportDateT    DATE,
    @SportBetTypeT  VARCHAR(MAX),
    @IsNoDrawT      BIT,
    @SiteNameT      VARCHAR(MAX),
    @MatchIDT       INT,
    @BetTypeT       INT
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
                , @LiveIndicator = 0
                , @MatchID       = @MatchIDT
    INSERT INTO #result
        EXEC dbo.Acc_Rpt_LeagueWL_Bettype_xtest
                  @StartDate  	 = @ReportDateT
                , @EndDate		 = @ReportDateT
                , @SportBettype  = @SportBettypeT
                , @IsNoDraw		 = @IsNoDrawT
                , @SiteName      = @SiteNameT
                , @LiveIndicator = 1
                , @MatchID       = @MatchIDT
    ------------------------------------------------------------
    INSERT INTO #actual
    SELECT  @MatchIDT,
            BetType                 BetType,
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
    WHERE BetType = @BetTypeT
    GROUP BY BetType
    ------------------------------------------------------------
    DROP TABLE #result
    ------------------------------------------------------------
END
GO

ALTER PROCEDURE testLeagueWinloss.[report by BetType from LeagueWL_Site] 
    @ReportDateT    DATE,
    @IsNoDrawT      BIT,
    @SiteNameT      VARCHAR(MAX),
    @MatchIDT       INT,
    @BetTypeT       INT
AS
BEGIN
    IF @MatchIDT IS NULL 
        EXEC tSQLt.Fail '@MatchIDT should not be NULL'
    ------------------------------------------------------------
    IF OBJECT_ID('tempdb..#result') IS NOT NULL DROP TABLE #result;
	CREATE TABLE #result (SiteID			INT,
						  SiteName		    VARCHAR(100),
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
        EXEC dbo.Acc_Rpt_LeagueWL_Site_xtest
                  @StartDate  	 = @ReportDateT
                , @EndDate		 = @ReportDateT
                , @IsNoDraw		 = @IsNoDrawT
                , @SiteName      = @SiteNameT
                , @LiveIndicator = 0
                , @MatchID       = @MatchIDT
                , @SiteType      = 'Credit'
                , @BetType       = @BetTypeT
    INSERT INTO #result
        EXEC dbo.Acc_Rpt_LeagueWL_Site_xtest
                  @StartDate  	 = @ReportDateT
                , @EndDate		 = @ReportDateT
                , @IsNoDraw		 = @IsNoDrawT
                , @SiteName      = @SiteNameT
                , @LiveIndicator = 0
                , @MatchID       = @MatchIDT
                , @SiteType      = 'Deposit'
                , @BetType       = @BetTypeT
    INSERT INTO #result
        EXEC dbo.Acc_Rpt_LeagueWL_Site_xtest
                  @StartDate  	 = @ReportDateT
                , @EndDate		 = @ReportDateT
                , @IsNoDraw		 = @IsNoDrawT
                , @SiteName      = @SiteNameT
                , @LiveIndicator = 0
                , @MatchID       = @MatchIDT
                , @SiteType      = 'CN88'
                , @BetType       = @BetTypeT

    INSERT INTO #result
        EXEC dbo.Acc_Rpt_LeagueWL_Site_xtest
                  @StartDate  	 = @ReportDateT
                , @EndDate		 = @ReportDateT
                , @IsNoDraw		 = @IsNoDrawT
                , @SiteName      = @SiteNameT
                , @LiveIndicator = 1
                , @MatchID       = @MatchIDT
                , @SiteType      = 'Credit'
                , @BetType       = @BetTypeT
    INSERT INTO #result
        EXEC dbo.Acc_Rpt_LeagueWL_Site_xtest
                  @StartDate  	 = @ReportDateT
                , @EndDate		 = @ReportDateT
                , @IsNoDraw		 = @IsNoDrawT
                , @SiteName      = @SiteNameT
                , @LiveIndicator = 1
                , @MatchID       = @MatchIDT
                , @SiteType      = 'Deposit'
                , @BetType       = @BetTypeT
    INSERT INTO #result
        EXEC dbo.Acc_Rpt_LeagueWL_Site_xtest
                  @StartDate  	 = @ReportDateT
                , @EndDate		 = @ReportDateT
                , @IsNoDraw		 = @IsNoDrawT
                , @SiteName      = @SiteNameT
                , @LiveIndicator = 1
                , @MatchID       = @MatchIDT
                , @SiteType      = 'CN88'
                , @BetType       = @BetTypeT
    ------------------------------------------------------------
    INSERT INTO #expected
    SELECT  @MatchIDT,
            @BetTypeT               BetType,
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