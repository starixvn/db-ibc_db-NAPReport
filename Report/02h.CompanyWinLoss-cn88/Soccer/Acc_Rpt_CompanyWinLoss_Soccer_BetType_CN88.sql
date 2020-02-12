/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_Soccer_BetType_CN88
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @IsMajor      BIT           = 1
   , @IsLive       INT           = 2
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
    BEGIN --#SportBetType     
	   DECLARE @isTest    BIT = 0;
	   SELECT @isTest = dbo.f_CheckSPVersion
			(@@PROCID);
	   CREATE TABLE #SportBetType(
		   BetType    INT);
	   INSERT INTO #SportBetType
			SELECT s.BetType
			FROM dbo.f_SportBetTypeMatrix_Sel
				(1, 1, 0, 2, '', '', @isTest) AS s
			WHERE LEN(SubProduct) = 0
				 AND EventType IN(1, 2);
    END;
    BEGIN -- Bet Type
	   DECLARE @BetType TABLE(
		   BetType         INT
		   PRIMARY KEY
		 , BetTypeName     NVARCHAR(50)
		 , DisplayOrder    INT IDENTITY(1, 1));
	   INSERT INTO @BetType(BetType)
	   VALUES
			(1),
			(301),
			(3),
			(302),
			(7),
			(303),
			(8),
			(304),
			(2),
			(5),
			(4),
			(6),
			(10);
	   INSERT INTO @BetType(BetType)
			SELECT typeid
			FROM BetType AS b WITH (NOLOCK)
			    INNER JOIN #SportBetType AS sb ON sb.BetType = b.typeid
			WHERE b.typeid > 10
				 AND b.typeid NOT IN(301, 302, 303, 304);
	   IF @IsMajor = 1
		  BEGIN
			 DELETE @BetType
			 WHERE Bettype NOT IN(1, 2, 3, 5, 6, 7, 8, 12, 15, 24, 25, 28, 121, 122, 123, 126, 151, 301, 302, 303, 304);
		  END;
		  ELSE
		  BEGIN
			 DELETE @BetType
			 WHERE Bettype IN(1, 2, 3, 5, 6, 7, 8, 12, 15, 24, 25, 28, 121, 122, 123, 126, 151, 301, 302, 303, 304);
		  END;
	   UPDATE b
			SET
			    b.BetTypeName = bt.typenamee
	   FROM @BetType b
		  INNER JOIN BetType
		   (NOLOCK) bt ON b.BetType = bt.typeid;
    END;
    BEGIN -- #Match
	   CREATE TABLE #Match(
		   MatchId      INT
		 , MatchCode    NVARCHAR(50)
		 , type         VARCHAR(10)
		 , PRIMARY KEY(MatchId, type));
	   INSERT INTO #Match
			SELECT DISTINCT
				  m.MatchId
				, m.MatchCode
				, m.type
			FROM
				(
				    SELECT MatchId
					    , LeagueId
					    , MatchCode
					    , 'match' AS type
				    FROM Match WITH (NOLOCK)
				    WHERE EventDate = @StartDate
				    UNION ALL
				    SELECT orid
					    , LeagueId
					    , MatchCode
					    , 'outright' AS type
				    FROM outright WITH (NOLOCK)
				    WHERE EventDate = @StartDate
				) AS m
			    INNER JOIN league AS l WITH (NOLOCK) ON m.LeagueId = l.LeagueId
			WHERE l.sporttype = 1;
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
				 AND a.ProductId = 1
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
	   CREATE TABLE #tmp_Data(
		   srecommend         INT
		 , bettype            INT
		 , liveindicator      BIT
		 , isHedgeMatch       BIT
		 , MemberWinLoss      MONEY
		 , SMAWinLoss         MONEY
		 , ExtraPT            MONEY
		 , Commission         MONEY
		 , RealIncome         MONEY
		 , VirtualIncome      MONEY
		 , VarianceIncome     MONEY
		 , RealTurnover       MONEY
		 , VirtualTurnover    MONEY);

	   CREATE TABLE #Data(
		   GroupId            INT
		 , GroupName          NVARCHAR(50)
		 , DisplayOrder       INT
		 , MemberWinLoss      MONEY
		 , SMAWinLoss         MONEY
		 , ExtraPT            MONEY
		 , Commission         MONEY
		 , RealIncome         MONEY
		 , VirtualIncome      MONEY
		 , VarianceIncome     MONEY
		 , RealTurnover       MONEY
		 , VirtualTurnover    MONEY);
    END;
    BEGIN -- Bet Type
	   INSERT INTO #tmp_Data(srecommend
					   , bettype
					   , liveindicator
					   , isHedgeMatch
					   , MemberWinLoss
					   , SMAWinLoss
					   , ExtraPT
					   , Commission
					   , RealIncome
					   , VirtualIncome
					   , VarianceIncome
					   , RealTurnover
					   , VirtualTurnover)
			SELECT srecommend
				, bettype
				, liveindicator
				, CASE
					 WHEN m.MatchCode LIKE '%hedge%'
					 THEN 1
					 ELSE 0
				  END AS isHedgeMatch
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
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
																	    WHEN tpositiontaking = 1
																	    THEN 0
																	    ELSE(winlost - actual_stake) * ISNULL(e.ExtraPT, 0)
																	END) * virtualrate + (scomm - CASE
																							    WHEN tpositiontaking = 1
																							    THEN 0
																							    ELSE b.scomm / (1 - b.tpositiontaking)
																							END * ISNULL(e.ExtraPT, 0)) * actualrate * CASE
																																  WHEN virtualrate < actualrate
																																  THEN virtualrate / actualrate
																																  ELSE 1
																															   END) AS VirtualIncome
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
																	    WHEN tpositiontaking = 1
																	    THEN 0
																	    ELSE(winlost - actual_stake) * ISNULL(e.ExtraPT, 0)
																	END + CASE
																			WHEN virtualrate < actualrate
																			THEN b.scomm - CASE
																						    WHEN tpositiontaking = 1
																						    THEN 0
																						    ELSE b.scomm / (1 - b.tpositiontaking)
																						END * ISNULL(e.ExtraPT, 0)
																			ELSE 0
																		 END) * (actualrate - virtualrate)) AS VarianceIncome
				, SUM(CASE
						WHEN tpositiontaking = 1
						THEN 0
						ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * CASE
																				  WHEN virtualrate > actualrate
																				  THEN virtualrate
																				  ELSE actualrate
																			   END
					 END) AS RealTurnover
				, SUM(CASE
						WHEN tpositiontaking = 1
						THEN 0
						ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * virtualrate
					 END) AS VirtualTurnover
			FROM bettrans AS b WITH (NOLOCK)
			    INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			    INNER JOIN #Match AS m ON b.MatchId = m.MatchId
			    LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
										AND e.Sporttype = 0
			WHERE b.winlostdate = @StartDate
				 AND m.type = CASE
							   WHEN b.BetType = 10
							   THEN 'outright'
							   ELSE 'match'
						    END
				 AND b.ruben = 1
				 AND b.statusID IN(111, 112, 113)
				 AND (@Headline = 0
					OR (@Headline = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					OR (@Headline = 2 AND EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					)
			GROUP BY srecommend
				  , bettype
				  , liveindicator
				  , CASE
					   WHEN m.MatchCode LIKE '%hedge%'
					   THEN 1
					   ELSE 0
				    END OPTION(RECOMPILE);

	   INSERT INTO #Data
			SELECT sb.BetType AS GroupId
				, CASE
					 WHEN b.isHedgeMatch = 1
					 THEN sb.BetTypeName+' (hedge)'
					 ELSE sb.BetTypeName
				  END AS GroupName
				, sb.DisplayOrder
				, SUM(MemberWinLoss) AS MemberWinLoss
				, SUM(SMAWinLoss) AS SMAWinLoss
				, SUM(ExtraPT) AS ExtraPT
				, SUM(Commission) AS Commission
				, SUM(RealIncome) AS RealIncome
				, SUM(VirtualIncome) AS VirtualIncome
				, SUM(VarianceIncome) AS VarianceIncome
				, SUM(RealTurnover) AS RealTurnover
				, SUM(VirtualTurnover) AS VirtualTurnover
			FROM #tmp_Data AS b WITH (NOLOCK)
			    INNER JOIN @BetType AS sb ON sb.BetType = b.BetType
			WHERE @IsLive > 1
				 OR b.liveindicator = @IsLive
			GROUP BY sb.BetType
				  , CASE
					   WHEN b.isHedgeMatch = 1
					   THEN sb.BetTypeName+' (hedge)'
					   ELSE sb.BetTypeName
				    END
				  , sb.DisplayOrder;
    END;

    BEGIN -- Query
	   SELECT d.GroupId AS GroupId
		   , d.GroupName AS GroupName
		   , d.DisplayOrder
		   , d.MemberWinLoss AS MemberWinLoss
		   , d.SMAWinLoss AS SMAWinLoss
		   , -d.ExtraPT AS HeadlineIncome
		   , d.Commission AS Commission
		   , d.RealIncome AS RealIncome
		   , d.VirtualIncome AS VirtualIncome
		   , d.VarianceIncome AS VarianceIncome
		   , d.RealTurnover AS RealTurnover
		   , d.VirtualTurnover AS VirtualTurnover
	   FROM #Data AS d
	   ORDER BY CASE
				 WHEN d.GroupName LIKE '%(hedge)%'
				 THEN 1
				 ELSE 0
			  END
			, DisplayOrder;
    END;

    DROP TABLE #SportBetType;
    DROP TABLE #Match;
    DROP TABLE #ExtraPT_Sel;
    DROP TABLE #Data;
    DROP TABLE #tmp_Data;
    DROP TABLE #tmp_XPG_SuperID;	
END;
GO