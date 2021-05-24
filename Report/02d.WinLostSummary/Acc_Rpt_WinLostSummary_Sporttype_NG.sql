/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_dwrs
GO
ALTER PROCEDURE dbo.Acc_Rpt_WinlostSummary_Sporttype_NG
	@fromdate     DATETIME
   , @todate       DATETIME
   , @SportType    SMALLINT = 0
   , @bettype      INT      = 0
AS
/*
        Created: Robert
        Date: 20181219
        Task: Get winlost summary details by match for Number Game
        DB: DBRPT/bodb_Report
        
        Revisions:
            20181219@Robert: NAP Report - Add new sporttype for Happy 5 (#104253) 
			20210420@Cherry: Renovation, change source table to DW (#153530)

        Parameter's Explanation:		
    */

SET NOCOUNT ON;

BEGIN

    DECLARE @RPT TABLE(
	    eventdate           DATETIME
	  , matchid             INT
	  , matchcode           NVARCHAR(50) COLLATE SQL_Latin1_General_CP1_CS_AS
	  , HomeId              INT
	  , AwayId              INT
	  , liveindicator       BIT
	  , bettype             SMALLINT
	  , leagueid            INT
	  , realWinLost         MONEY
	  , realPosition        MONEY
	  , realCommission      MONEY
	  , realTurnover        MONEY
	  , realLineTotal       MONEY
	  , virtualTurnover     MONEY
	  , virtualLineTotal    MONEY
	  , isNeutral           BIT
	  , orderkey            TINYINT);

    DECLARE @SportBettype TABLE(
	    ProductID     INT
	  , Bettype       INT
	  , EventType     INT
	  , SubProduct    VARCHAR(500));
    INSERT INTO @SportBettype
		 SELECT DISTINCT
			   ProductID
			 , Bettype
			 , EventType
			 , SubProduct
		 FROM bodb02.dbo.SportBettypeMatrix
		 WHERE ProductID = 3
			  AND SportType = CASE
							  WHEN @bettype = 0
							  THEN SportType
							  ELSE @SportType
						   END;

    DECLARE @movebetdate    DATETIME
		, @f_date         DATETIME
		, @t_date         DATETIME;

    SELECT @movebetdate = MoveBetsDay
	FROM OPENQUERY(DBACC,'EXEC bodb02.dbo.Age_SelBalanceUpDay')
	
    IF @todate > @movebetdate
	   BEGIN
		  IF @fromdate <= @movebetdate
			 SELECT @f_date = @movebetdate + 1;
			 ELSE
		  SELECT @f_date = @fromdate;
		  SELECT @t_date = @todate;

		  INSERT INTO @RPT(eventdate
					  , matchid
					  , matchcode
					  , homeid
					  , awayid
					  , liveindicator
					  , bettype
					  , leagueid
					  , realWinlost
					  , realPosition
					  , realCommission
					  , realTurnover
					  , realLineTotal
					  , virtualTurnover
					  , virtualLineTotal
					  , isNeutral)
			    SELECT m.eventdate
				    , b.matchid
				    , matchcode
				    , homeid
				    , awayid
				    , 0 AS liveindicator
				    , b.bettype
				    , m.leagueid
				    , ISNULL(SUM(realWinlost), 0)
				    , ISNULL(SUM(realPosition), 0)
				    , ISNULL(SUM(realCommission), 0)
				    , ISNULL(SUM(realTurnover), 0)
				    , ISNULL(SUM(realLineTotal), 0)
				    , ISNULL(SUM(virtualTurnover), 0)
				    , ISNULL(SUM(virtualLineTotal), 0)
				    , m.isNeutral
			    FROM bodb_Account.dbo.rptWinlost AS b WITH (NOLOCK)
				   INNER JOIN bodb02.dbo.match AS m WITH (NOLOCK) ON b.matchid = m.matchid
				   INNER JOIN @SportBettype AS sb ON sb.Bettype = b.bettype
			    WHERE winlostdate BETWEEN @f_date AND @t_date
					AND m.matchcode NOT LIKE '%hedge%'
					AND B.IBC = 0
			    GROUP BY eventdate
					 , b.matchid
					 , matchcode
					 , homeid
					 , awayid
					 , b.bettype
					 , leagueid
					 , isNeutral;
	   END;
    IF @fromdate <= @movebetdate
	   BEGIN
		  IF @todate <= @movebetdate
			 SELECT @t_date = @todate;
			 ELSE
		  SELECT @t_date = @movebetdate;
		  SELECT @f_date = @fromdate;

		  INSERT INTO @RPT(eventdate
					  , matchid
					  , matchcode
					  , homeid
					  , awayid
					  , liveindicator
					  , bettype
					  , leagueid
					  , realWinlost
					  , realPosition
					  , realCommission
					  , realTurnover
					  , realLineTotal
					  , virtualTurnover
					  , virtualLineTotal
					  , isNeutral)
			    SELECT m.eventdate
				    , b.matchid
				    , matchcode
				    , homeid
				    , awayid
				    , 0 AS liveindicator
				    , b.bettype
				    , m.leagueid
				    , ISNULL(SUM(realWinlost), 0)
				    , ISNULL(SUM(realPosition), 0)
				    , ISNULL(SUM(realCommission), 0)
				    , ISNULL(SUM(realTurnover), 0)
				    , ISNULL(SUM(realLineTotal), 0)
				    , ISNULL(SUM(virtualTurnover), 0)
				    , ISNULL(SUM(virtualLineTotal), 0)
				    , m.isNeutral
			    FROM bodb_Account.dbo.rptWinlost AS b WITH (NOLOCK)
				   INNER JOIN bodb_archive.dbo.match AS m WITH (NOLOCK) ON b.matchid = m.matchid
				   INNER JOIN @SportBettype AS sb ON sb.Bettype = b.bettype
			    WHERE winlostdate BETWEEN @f_date AND @t_date
					AND m.matchcode NOT LIKE '%hedge%'
					AND B.IBC = 0
			    GROUP BY eventdate
					 , b.matchid
					 , matchcode
					 , homeid
					 , awayid
					 , b.bettype
					 , leagueid
					 , isNeutral;
	   END;


    SELECT '' AS HedgeGroup
	    , 0 AS  IsHedge
	    , r.*
    FROM @RPT AS r
    ORDER BY r.orderkey
		 , r.HomeId
		 , r.AwayId
		 , r.leagueid
		 , r.matchcode
		 , r.bettype;
END;
GO

