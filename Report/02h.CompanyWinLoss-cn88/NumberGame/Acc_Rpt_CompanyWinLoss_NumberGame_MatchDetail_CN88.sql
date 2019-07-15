/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_NumberGame_MatchDetail_CN88
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @LeagueId     INT
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
    CREATE TABLE #ExtraPT_Sel(
	    SuperID    INT
	  , ExtraPT    DECIMAL(9, 8));
    INSERT INTO #ExtraPT_Sel(SuperID
					  , ExtraPT)
		 SELECT SuperId
			 , SUM(ExtraPT) AS ExtraPT
		 FROM bodb02.dbo.Acc_GroupExtraPTSetting AS a WITH (NOLOCK)
		 WHERE @StartDate BETWEEN FromDate AND Todate
			  AND a.ProductId = 3
			  AND SuperId IN
						  (
							 SELECT CustId
							 FROM CS_CustSuper WITH (NOLOCK)
						  )
			  AND SubProduct = ''
		 GROUP BY SuperId;
    BEGIN -- #Data
	   CREATE TABLE #Data(
		   LeagueId         INT
		 , MatchCode        NVARCHAR(50)
		 , MemberWinLoss    MONEY
		 , SMAWinLoss       MONEY
		 , ExtraPT          MONEY
		 , Commission       MONEY
		 , RealIncome       MONEY
		 , RealTurnover     MONEY);
    END;
    BEGIN -- Insert Into #Data
	   INSERT INTO #Data
			SELECT m.LeagueId
				, m.MatchCode
				, SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss
				, SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
					 END * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT
				, SUM(scomm * actualrate) AS Commission
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
																			  WHEN tpositiontaking = 1
																			  THEN 0
																			  ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																		   END * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome
				, SUM(CASE
						WHEN tpositiontaking = 1
						THEN 0
						ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
																			  WHEN virtualrate > actualrate
																			  THEN virtualrate
																			  ELSE actualrate
																		   END
					 END) AS RealTurnover
			FROM bettrans AS b WITH (nolock)
			    INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			    INNER JOIN match AS m WITH (nolock) ON b.MatchId = m.MatchId
			    LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
			WHERE b.winlostdate = @StartDate
				 AND m.leagueid = @LeagueId
				 AND b.BetType = @BetType
				 AND b.MatchId > 0
				 AND b.ruben = 1
				 AND statusID IN(111, 112, 113)
			GROUP BY m.MatchCode
				  , m.LeagueId;
    END;
    BEGIN -- Query      
	   SELECT l.leaguename AS GroupName
		   , d.MatchCode AS RowName
		   , d.MemberWinLoss
		   , d.SMAWinLoss
		   , -d.ExtraPT AS HeadlineIncome
		   , d.Commission
		   , d.RealIncome
		   , d.RealTurnover
	   FROM #Data AS d
		  INNER JOIN league AS l WITH (nolock) ON l.LeagueId = d.LeagueId
	   ORDER BY GroupName
			, RowName;
    END;
    DROP TABLE #ExtraPT_Sel;
    DROP TABLE #Data;
END;