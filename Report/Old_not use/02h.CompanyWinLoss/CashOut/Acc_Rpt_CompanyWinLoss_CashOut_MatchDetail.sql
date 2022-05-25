USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_MatchDetail] 
	@StartDate SMALLDATETIME, 
    @EndDate   SMALLDATETIME, 
	@SportType INT      = 1,
    @IsLive    INT           = 2
AS

/*
Creator: Cherry
Date: 2020-03-20
Task:  Support Deadball Cash Out (#130302)
DB: DBACC/bodb02

Revisions:
	20200320@Cherry: Initial
	20210812@Kean: Cashout For Basketball (#146083)

Parameters:
@IsLive: 2 - ALL. 0 - Non-Live. 1 - Live
Example:
EXEC [Acc_Rpt_CompanyWinLoss_CashOut_MatchDetail] @EndDate='2020-01-01',@StartDate='2016-01-01', @IsLive = 2

*/

    SET NOCOUNT ON;

    CREATE TABLE #Match
                 (MatchId   INT, 
                  MatchCode NVARCHAR(50), 
                  IsNeutral BIT, 
                  EventDate DATETIME, 
                  SportType INT, 
                  LeagueId  INT, 
                  HomeId    INT, 
                  AwayId    INT
                 );
    INSERT INTO #Match
    SELECT m.MatchId, 
          m.MatchCode, 
          m.IsNeutral, 
          m.EventDate, 
          m.SportType, 
          m.LeagueId, 
          m.HomeId, 
          m.AwayId
    FROM Match m WITH(NOLOCK)
	INNER JOIN league AS l WITH(NOLOCK) ON m.LeagueId = l.LeagueId
    WHERE EventDate = @StartDate
		 AND l.sporttype = @SportType

    CREATE TABLE #Data
                 (MatchId         INT, 
                  MatchCode       VARCHAR(100), 
                  IsNeutral       BIT, 
                  EventDate       DATETIME, 
                  SportType       INT, 
                  LeagueId        INT, 
                  HomeId          INT, 
                  AwayId          INT, 
                  MemberWinLoss   MONEY, 
                  SMAWinLoss      MONEY, 
                  ExtraPT         MONEY, 
                  Commission      MONEY, 
                  RealIncome      MONEY,  
                  RealTurnover    MONEY
                 )

    INSERT INTO #Data
    SELECT b.MatchId, 
          m.MatchCode, 
          ISNULL(m.IsNeutral, 0) AS IsNeutral, 
          m.EventDate, 
          m.SportType, 
          m.LeagueId, 
          m.HomeId, 
          m.AwayId, 
          SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
          SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
          SUM((CASE
                   WHEN b.tpositiontaking = 1
                   THEN 0
                   ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
               END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT, 
          SUM(scomm * actualrate) Commission, 
          SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                      WHEN tpositiontaking = 1
                                                                                      THEN 0
                                                                                      ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                  END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) RealIncome, 
          SUM(CASE
                  WHEN tpositiontaking = 1
                  THEN 0
                  ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * CASE
                                                                                          WHEN virtualrate > actualrate
                                                                                          THEN virtualrate
                                                                                          ELSE actualrate
                                                                                      END
              END) RealTurnover
    FROM bettrans b WITH(NOLOCK)
        INNER JOIN #Match m  ON b.MatchId = m.MatchId
    WHERE b.winlostdate = @StartDate
         AND b.bettype IN (913,914)
         AND m.EventDate = @StartDate
         AND (@IsLive > 1
              OR b.liveindicator = @IsLive)
         AND b.MatchId > 0
         AND b.ruben = 1
         AND statusID IN(111, 112, 113)
		 
    GROUP BY b.MatchId, 
            m.MatchCode, 
            m.IsNeutral, 
            m.EventDate, 
            m.SportType, 
            m.LeagueId, 
            m.HomeId, 
            m.AwayId, 
            m.LeagueId
                
    OPTION(RECOMPILE)

    SELECT d.MatchId, 
           d.MatchCode, 
           d.IsNeutral, 
           d.EventDate, 
           d.SportType, 
           d.LeagueId, 
           d.HomeId, 
           d.AwayId, 
           d.MemberWinLoss AS MemberWinLoss, 
           d.SMAWinLoss AS SMAWinLoss, 
           -d.ExtraPT AS ExtraPT, 
           d.Commission AS Commission, 
           d.RealIncome AS RealIncome, 
           d.RealTurnover AS RealTurnover
    FROM #Data AS d
    ORDER BY LeagueId, 
             MatchCode;

    DROP TABLE #Match;
    DROP TABLE #Data;
GO