/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_dwrs
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostSummary_Sporttype_BF] @fromdate DATETIME,
                                                            @todate   DATETIME
AS    

/*
        Created: Robert
        Date: 2017-11-10
        Task: Get winlost summary details by match for Bullfighting
        DB: DBRPT/bodb_Report
        
        Revisions:
            - 20170323@Robert: NAP Reports - Integrate Cash out [RedmindID: #73419]
            - 20210420@Cherry: Renovation, change source table to DW (#153530)
        
	   Parameter's Explanation:		
    */

     SET NOCOUNT ON;
     DECLARE @RPT TABLE
     (eventdate        DATETIME,
      matchid          INT,
      matchcode        NVARCHAR(50) COLLATE SQL_Latin1_General_CP1_CS_AS,
      HomeId           INT,
      AwayId           INT,
      liveindicator    BIT,
      bettype          SMALLINT,
      leagueid         INT,
      LeagueCode       NVARCHAR(50),
      realWinLost      MONEY,
      realPosition     MONEY,
      realCommission   MONEY,
      realTurnover     MONEY,
      realLineTotal    MONEY,
      virtualTurnover  MONEY,
      virtualLineTotal MONEY,
      isNeutral        BIT,
      orderkey         TINYINT
     );
     DECLARE @isTest BIT= 0;
     SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
     DECLARE @SportBettype TABLE
     (ProductID  INT,
      Bettype    INT,
      EventType  INT,
      SubProduct VARCHAR(500)
     );
     INSERT INTO @SportBettype
            SELECT ProductID,
                   Bettype,
                   EventType,
                   SubProduct
            FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest)
            WHERE ProductID = 30;
     DECLARE @movebetdate DATETIME, @f_date DATETIME, @t_date DATETIME;
     
     SELECT @movebetdate = MoveBetsDay
	 FROM OPENQUERY(DBACC,'EXEC bodb02.dbo.Age_SelBalanceUpDay')

     IF @todate > @movebetdate
         BEGIN	    		  
             IF @fromdate <= @movebetdate
                 SELECT @f_date = @movebetdate + 1;
             ELSE
             SELECT @f_date = @fromdate;
             SELECT @t_date = @todate;
             INSERT INTO @RPT
             (eventdate,
              matchid,
              matchcode,
              homeid,
              awayid,
              liveindicator,
              bettype,
              leagueid,
              LeagueCode,
              realWinlost,
              realPosition,
              realCommission,
              realTurnover,
              realLineTotal,
              virtualTurnover,
              virtualLineTotal,
              isNeutral
             )
                    SELECT m.eventdate,
                           b.matchid,
                           m.MatchNo AS matchcode,
                           homeid,
                           awayid,
                           b.liveindicator,
                           b.bettype,
                           m.League3rdId AS leagueid,
                           l.LeagueCode,
                           ISNULL(SUM(realWinlost), 0),
                           ISNULL(SUM(realPosition), 0),
                           ISNULL(SUM(realCommission), 0),
                           ISNULL(SUM(realTurnover), 0),
                           ISNULL(SUM(realLineTotal), 0),
                           ISNULL(SUM(virtualTurnover), 0),
                           ISNULL(SUM(virtualLineTotal), 0),
                           0 AS isNeutral
                    FROM bodb_Account.dbo.rptWinlost b WITH (NOLOCK)
                         INNER JOIN @SportBettype sb ON b.bettype = sb.Bettype
                         INNER JOIN bodb02.dbo.Match3rd m WITH (NOLOCK) ON b.matchid = m.Match3rdId
                         INNER JOIN bodb02.dbo.League3rd l WITH (nolock) ON l.League3rdId = m.League3rdId
                    WHERE winlostdate BETWEEN @f_date AND @t_date
                          AND sb.ProductID = 30
                    GROUP BY eventdate,
                             b.matchid,
                             m.MatchNo,
                             homeid,
                             awayid,
                             liveindicator,
                             b.bettype,
                             m.League3rdId,
                             l.LeagueCode;
         END;
     IF @fromdate <= @movebetdate	   
         BEGIN
             IF @todate <= @movebetdate
                 SELECT @t_date = @todate;
             ELSE
             SELECT @t_date = @movebetdate;
             SELECT @f_date = @fromdate;
             INSERT INTO @RPT
             (eventdate,
              matchid,
              matchcode,
              homeid,
              awayid,
              liveindicator,
              bettype,
              leagueid,
              LeagueCode,
              realWinlost,
              realPosition,
              realCommission,
              realTurnover,
              realLineTotal,
              virtualTurnover,
              virtualLineTotal,
              isNeutral
             )
                    SELECT m.eventdate,
                           b.matchid,
                           m.MatchNo AS matchcode,
                           homeid,
                           awayid,
                           b.liveindicator,
					  b.bettype,                           
                           m.League3rdId AS leagueid,
					  l.LeagueCode,                           
                           ISNULL(SUM(realWinlost), 0),
                           ISNULL(SUM(realPosition), 0),
                           ISNULL(SUM(realCommission), 0),
                           ISNULL(SUM(realTurnover), 0),
                           ISNULL(SUM(realLineTotal), 0),
                           ISNULL(SUM(virtualTurnover), 0),
                           ISNULL(SUM(virtualLineTotal), 0),
                           0 AS isNeutral
                    FROM bodb_Account.dbo.rptWinlost b WITH (NOLOCK)
                         INNER JOIN @SportBettype sb ON b.bettype = sb.Bettype
                         INNER JOIN bodb02.dbo.Match3rd14 m WITH (NOLOCK) ON b.matchid = m.Match3rdId
                         INNER JOIN bodb02.dbo.League3rd l WITH (nolock) ON l.League3rdId = m.League3rdId
                    WHERE winlostdate BETWEEN @f_date AND @t_date
                          AND sb.ProductID = 30
                    GROUP BY eventdate,
                             b.matchid,
                             m.MatchNo,
                             homeid,
                             awayid,
                             liveindicator,
                             b.bettype,
                             m.League3rdId,
                             l.LeagueCode;
         END;

     -- select result
     SELECT eventdate,
            matchid,
            matchcode,
            homeid,
            awayid,
            liveindicator,
            bettype,
            leagueid,
            LeagueCode,
            realWinlost,
            realPosition,
            realCommission,
            realTurnover,
            realLineTotal,
            virtualTurnover,
            virtualLineTotal,
            isNeutral
     FROM @RPT;
GO
