/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_SystemParlay_CN88_14
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @Site         NVARCHAR(20)  = 'ALL'
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
				 AND a.Sporttype = 0
				 AND SuperId IN
							 (
								SELECT CustId
								FROM CS_CustSuper WITH (NOLOCK)
							 )
				 AND SubProduct = ''
			GROUP BY SuperId
				  , Sporttype;
    END;
    BEGIN -- #Data
	   CREATE TABLE #Data(
		   GroupName          NVARCHAR(50)
		 , RowName            NVARCHAR(50)
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
    
    CREATE TABLE #tmp_XPG_SuperID(SuperID INT)
		  
	INSERT INTO #tmp_XPG_SuperID(SuperID)
	SELECT SuperId
	FROM bodb02.dbo.f_GetHeadlineNoPT()

    INSERT INTO #Data
		 SELECT CASE liveawayscore
				  WHEN 1
				  THEN 'Soccer Sport Total'
				  WHEN 2
				  THEN 'Others Sport Total'
				  WHEN 3
				  THEN 'Multi Sport Total'
				  ELSE ''
			   END AS GroupName
			 , 'System Parlay('+status+')' AS RowName
			 , SUM((winlost - actual_stake) * actualrate) AS MemberWinLost
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
		 FROM bettrans14 AS b WITH (NOLOCK)
			INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
		 WHERE b.winlostdate = @StartDate
			  AND BetType = 29
			  AND betteam <> '1'
			  AND ruben = 1
			  AND statusID IN(111, 112, 113)
			  AND (@Headline = 0
					OR (@Headline = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					OR (@Headline = 2 AND EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					)	
		 GROUP BY 'System Parlay('+status+')'
			   , CASE liveawayscore
				    WHEN 1
				    THEN 'Soccer Sport Total'
				    WHEN 2
				    THEN 'Others Sport Total'
				    WHEN 3
				    THEN 'Multi Sport Total'
				    ELSE ''
				END;


    BEGIN -- Query
	   SELECT d.GroupName AS GroupName
		   , d.RowName AS RowName
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
	   ORDER BY GroupName DESC
			, RowName;
    END;
    DROP TABLE #Data;
    DROP TABLE #ExtraPT_Sel;
    DROP TABLE #tmp_XPG_SuperID;	
END;
GO