/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_VirtualRacing_MatchDetail_CN88
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @SportType    SMALLINT
   , @BetType      INT
   , @Headline	  INT
AS
/*	
    Creator: Robert
	Date: 2016-05-11
	Task: Company Winloss Report - Main SP [Redmine: #116083]
	DB: DBACC/bodb02	
		
	Revisions:
		20190710@Robert: 	NAP Report - Implement new report to match with CN88's need [#116083]
		20200214@Cherry: Add filter by Headline Group (#127822)
	Explanation's Param:	
		@Headline = 0 : All, 
				  = 1 : TPG,
				  = 2 : XPG
*/
BEGIN
    SET NOCOUNT ON;
    BEGIN -- #Data
	   CREATE TABLE #Data(
		   LeagueId         INT
		 , EventType        DATETIME
		 , MemberWinLoss    MONEY
		 , SMAWinLoss       MONEY
		 , ExtraPT          MONEY
		 , Commission       MONEY
		 , RealIncome       MONEY
		 , RealTurnover     MONEY);
    END;
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
				 AND a.ProductId = 5
				 AND SuperId IN
							 (
								SELECT CustId
								FROM CS_CustSuper WITH (NOLOCK)
							 )
				 AND SubProduct = ''
			GROUP BY SuperId
				  , Sporttype;
    END;
    
    CREATE TABLE #tmp_XPG_SuperID(SuperID INT)
		  
	INSERT INTO #tmp_XPG_SuperID(SuperID)
	SELECT SuperId
	FROM bodb02.dbo.f_GetHeadlineNoPT()
	
    BEGIN -- #Data
	   INSERT INTO #Data
			SELECT r.LeagueId
				, r.EventTime
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
			    INNER JOIN VSRaceInfo AS r WITH (nolock) ON b.MatchId = r.EventId
			    LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
			WHERE b.winlostdate = @StartDate
				 AND b.BetType = @BetType
				 AND r.SportType = @SportType
				 AND b.MatchId > 0
				 AND b.ruben = 1
				 AND b.statusID IN(111, 112, 113)
				 AND (@Headline = 0
					OR (@Headline = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					OR (@Headline = 2 AND EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					)
			GROUP BY r.LeagueId
				  , r.EventTime;
    END;
    BEGIN -- Query
	   SELECT l.leaguename AS GroupName
		   , l.LeagueId AS GroupId
		   , SUBSTRING(CONVERT(VARCHAR, d.EventType, 108), 1, 5) AS RowName
		   , d.MemberWinLoss AS MemberWinLoss
		   , d.SMAWinLoss AS SMAWinLoss
		   , -d.ExtraPT AS HeadlineIncome
		   , d.Commission AS Commission
		   , d.RealIncome AS RealIncome
		   , d.RealTurnover AS RealTurnover
	   FROM #Data AS d
		  INNER JOIN league AS l WITH (NOLOCK) ON d.LeagueId = l.LeagueId
	   ORDER BY GroupName
			, RowName;
    END;
    DROP TABLE #Data;
    DROP TABLE #ExtraPT_Sel;
    DROP TABLE #tmp_XPG_SuperID;	
END;
GO