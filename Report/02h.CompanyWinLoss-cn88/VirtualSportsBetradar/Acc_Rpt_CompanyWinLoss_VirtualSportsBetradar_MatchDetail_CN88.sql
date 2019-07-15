/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_VirtualSportsBetradar_MatchDetail_CN88
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @SportType    SMALLINT
   , @BetType      INT
AS
/*	
    Creator: Robert
	Date: 2016-05-11
	Task: Company Winloss Report - Main SP [Redmine: #116083]
	DB: DBACC/bodb02	
		
	Revisions:
		- 20190710@Robert: 	NAP Report - Implement new report to match with CN88's need [#116083]
	Explanation's Param:	
*/
BEGIN

    SET NOCOUNT ON;
    BEGIN ---- Extra PT 
	   CREATE TABLE #ExtraPT_Sel(
		   SuperID      INT
		 , Sporttype    INT
		 , ExtraPT      DECIMAL(9, 8));
	   INSERT INTO #ExtraPT_Sel(SuperID
						 , Sporttype
						 , ExtraPT)
			SELECT SuperId
				, Sporttype
				, SUM(ExtraPT) AS ExtraPT
			FROM bodb02.dbo.Acc_GroupExtraPTSetting AS a WITH (NOLOCK)
			WHERE @StartDate BETWEEN FromDate AND Todate
				 AND a.ProductId = 27
				 AND SuperId IN
							 (
								SELECT CustId
								FROM CS_CustSuper WITH (NOLOCK)
							 )
				 AND SubProduct = ''
			GROUP BY SuperId
				  , Sporttype;
    END;
    BEGIN
	   CREATE TABLE #Data(
		   LeagueId         INT
		 , MatchId          INT
		 , MatchCode        NVARCHAR(50)
		 , HomeId           INT
		 , AwayId           INT
		 , MemberWinLoss    MONEY
		 , SMAWinLoss       MONEY
		 , ExtraPT          MONEY
		 , Commission       MONEY
		 , RealIncome       MONEY
		 , RealTurnover     MONEY);
	   INSERT INTO #Data
			SELECT m.leagueid
				, m.matchid
				, m.matchcode
				, m.homeid
				, m.awayid
				, SUM((winlost - actual_stake) * actualrate)
				, SUM((awinlost + mwinlost + swinlost) * actualrate)
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
					 END * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT
				, SUM(scomm * actualrate)
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
																			  WHEN tpositiontaking = 1
																			  THEN 0
																			  ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																		   END * ISNULL(e.ExtraPT, 0)) * actualrate)
				, SUM(CASE
						WHEN tpositiontaking = 1
						THEN 0
						ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
																			  WHEN virtualrate > actualrate
																			  THEN virtualrate
																			  ELSE actualrate
																		   END
					 END)
			FROM bettrans AS b WITH (nolock)
			    INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			    INNER JOIN match AS m WITH (nolock) ON b.MatchId = m.MatchId
			    LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
			WHERE b.winlostdate = @StartDate
				 AND b.bettype = @BetType
				 AND m.sporttype = @SportType
				 AND b.matchid > 0
				 AND b.ruben = 1
				 AND statusID IN(111, 112, 113)
			GROUP BY m.matchid
				  , m.matchcode
				  , m.homeid
				  , m.awayid
				  , m.leagueid
			ORDER BY m.leagueid
				  , m.matchcode
				  , m.homeid
				  , m.awayid;
    END;
    BEGIN -- Query
	   SELECT d.MatchId
		   , d.MatchCode
		   , d.HomeId
		   , d.AwayId
		   , d.LeagueId
		   , d.MemberWinLoss AS MemberWinLoss
		   , d.SMAWinLoss AS SMAWinLoss
		   , -d.ExtraPT AS HeadlineIncome
		   , d.Commission AS Commission
		   , d.RealIncome AS RealIncome
		   , d.RealTurnover AS RealTurnover
	   FROM #Data AS d;
    END;
    DROP TABLE #ExtraPT_Sel;
    DROP TABLE #Data;
END;
GO