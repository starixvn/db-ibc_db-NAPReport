/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_VirtualSports_BetType_CN88
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @SportType    SMALLINT
   , @Headline	  INT
AS
/*	
    Creator: Robert
	Date: 2016-05-11
	Task: Company Winloss Report - Main SP [Redmine: #116083]
	DB: DBACC/bodb02	
		
	Revisions:
		20190710@Robert: 	NAP Report - Implement new report to match with CN88's need [#116083]
		20191212@Ned.Le:  Support to get Extra PT from Extra PT column [#125286]
		20200214@Cherry: Add filter by Headline Group (#127822)
		
	Explanation's Param:	
		@Headline = 0 : All, 
				  = 1 : TPG,
				  = 2 : XPG
*/
BEGIN
    SET NOCOUNT ON;
    BEGIN --#SportBetType     
	   DECLARE @isTest    BIT = 0;
	   SELECT @isTest = dbo.f_CheckSPVersion
			(@@PROCID);
	   CREATE TABLE #SportBetType(
		   BetType        INT
		 , BetTypeName    NVARCHAR(50)
		 , EventType      INT);
	   INSERT INTO #SportBetType
			SELECT b.typeid
				, b.typenamee
				, s.EventType
			FROM dbo.f_SportBetTypeMatrix_Sel
				(5, @SportType, 0, 2, '', '', @isTest) AS s
			    INNER JOIN BetType AS b WITH (NOLOCK) ON s.BetType = b.typeid
			WHERE s.SubProduct = '';
    END;
    
    CREATE TABLE #tmp_XPG_SuperID(SuperID INT)
		  
	INSERT INTO #tmp_XPG_SuperID(SuperID)
	SELECT SuperId
	FROM bodb02.dbo.f_GetHeadlineNoPT()

    IF EXISTS -- Virtual Sportsbook
		    (
			   SELECT 1
			   FROM #SportBetType
			   WHERE EventType = 1
		    )
	   BEGIN
		  SELECT sb.BetType AS GroupId
			  , sb.BetTypeName AS GroupName
			  , SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss
			  , SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss
			  , -SUM(CASE
					   WHEN b.tpositiontaking = 1
					   THEN 0
					   ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
				    END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS HeadlineIncome
			  , SUM(scomm * actualrate) AS Commission
			  , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
																		    WHEN tpositiontaking = 1
																		    THEN 0
																		    ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																		END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome
			  , SUM(CASE
					  WHEN tpositiontaking = 1
					  THEN 0
					  ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.stake * CASE
																		    WHEN virtualrate > actualrate
																		    THEN virtualrate
																		    ELSE actualrate
																		END
				   END) AS RealTurnover
		  FROM bettrans AS b WITH (NOLOCK)
			 INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			 INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
			 INNER JOIN match AS m WITH (NOLOCK) ON b.MatchId = m.MatchId
		  WHERE b.winlostdate = @StartDate
			   AND m.sporttype = @SportType
			   AND b.MatchId > 0
			   AND b.ruben = 1
			   AND b.statusID IN(111, 112, 113)
			   AND (@Headline = 0
					OR (@Headline = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					OR (@Headline = 2 AND EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					)
		  GROUP BY sb.BetType
			    , sb.BetTypeName
		  ORDER BY GroupName;
	   END;
	   ELSE -- Virtual Racing
	   BEGIN
		  SELECT sb.BetType AS GroupId
			  , sb.BetTypeName AS GroupName
			  , SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss
			  , SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss
			  , -SUM((CASE
					    WHEN b.tpositiontaking = 1
					    THEN 0
					    ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
					END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS HeadlineIncome
			  , SUM(scomm * actualrate) Commission
			  , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
																			WHEN tpositiontaking = 1
																			THEN 0
																			ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																		 END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome
			  , SUM(CASE
					  WHEN tpositiontaking = 1
					  THEN 0
					  ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.stake * CASE
																		    WHEN virtualrate > actualrate
																		    THEN virtualrate
																		    ELSE actualrate
																		END
				   END) AS RealTurnover
		  FROM bettrans AS b WITH (NOLOCK)
			 INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			 INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
			 INNER JOIN VSRaceInfo AS r WITH (NOLOCK) ON r.EventId = b.MatchId
		  WHERE b.winlostdate = @StartDate
			   AND r.sporttype = @SportType
			   AND b.MatchId > 0
			   AND b.ruben = 1
			   AND b.statusID IN(111, 112, 113)
			   AND (@Headline = 0
					OR (@Headline = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					OR (@Headline = 2 AND EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					)
		  GROUP BY sb.BetType
			    , sb.BetTypeName
		  ORDER BY GroupName
	   END;

    DROP TABLE #SportBetType;
    DROP TABLE #tmp_XPG_SuperID;
    
END;
GO