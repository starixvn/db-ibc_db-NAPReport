/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE Acc_Rpt_CompanyWinLoss_Soccer_Minor
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
AS
/*
Creator: Robert
Date: 2018-09-20
Task:  2h Soccer Minor Bettype [#100617]
DB: DBACC/bodb02

Revisions:
    20180920@Robert: Apply new concept for Virtual & Extra PT on 2h Soccer Minor Bettype [#100617]
    20190308@Cherry: Integrate Bet Builder (#109822)
	20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)

Parameters:

Example:

*/

SET NOCOUNT ON;
BEGIN /* #SportBetType	*/

    DECLARE @isTest    BIT = 0;
    SELECT @isTest = dbo.f_CheckSPVersion
		 (@@PROCID);
    CREATE TABLE #SportBetType(
	    BetType    INT
	  , IsMajor    BIT);
    INSERT INTO #SportBetType
		 SELECT BetType
			 , 0
		 FROM bodb02.dbo.f_SportBetTypeMatrix_Sel
			 (1, 1, 0, 2, '', '', @isTest)
		 WHERE EventType IN(1, 2)
			  AND SubProduct NOT IN('MG-SuperLive', 'BT-Sold', 'BT-Bought', 'BT-Comm', 'BT-Winloss', 'Bet Builder')
			  AND bettype NOT IN(1, 3, 7, 8, 122, 123, 151, 301, 302, 303, 304);
END;
BEGIN /* #DepositSuper*/


    CREATE TABLE #DepositSuper(
	    CustId    INT
	    PRIMARY KEY);
    INSERT INTO #DepositSuper
		 SELECT CustId
		 FROM f_DepSuper_1
			 ('All');
END;
BEGIN /* #Match*/


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
				FROM dbo.Match WITH (NOLOCK)
				WHERE EventDate = @StartDate
				UNION ALL
				SELECT orid
					, LeagueId
					, MatchCode
					, 'outright' AS type
				FROM dbo.outright WITH (NOLOCK)
				WHERE EventDate = @StartDate
			 ) AS m
			INNER JOIN dbo.league AS l WITH (NOLOCK) ON m.LeagueId = l.LeagueId
		 WHERE l.sporttype = 1;
END;
BEGIN /* #Data*/

    CREATE TABLE #tmp_Data(
	    srecommend         INT
	  , bettype            INT
	  , liveindicator      BIT
	  , MemberWinLoss      DECIMAL(19, 6)
	  , SMAWinLoss         DECIMAL(19, 6)
	  , ExtraPT            DECIMAL(19, 6)
	  , Commission         DECIMAL(19, 6)
	  , RealIncome         DECIMAL(19, 6)
	  , VirtualIncome      DECIMAL(19, 6)
	  , VarianceIncome     DECIMAL(19, 6)
	  , RealTurnover       DECIMAL(19, 6)
	  , VirtualTurnover    DECIMAL(19, 6));
    CREATE TABLE #Data(
	    GroupId            INT
	  , GroupName          NVARCHAR(50)
	  , RowName            NVARCHAR(50)
	  , MemberWinLoss      DECIMAL(19, 6)
	  , SMAWinLoss         DECIMAL(19, 6)
	  , ExtraPT            DECIMAL(19, 6)
	  , Commission         DECIMAL(19, 6)
	  , RealIncome         DECIMAL(19, 6)
	  , VirtualIncome      DECIMAL(19, 6)
	  , VarianceIncome     DECIMAL(19, 6)
	  , RealTurnover       DECIMAL(19, 6)
	  , VirtualTurnover    DECIMAL(19, 6));
END;
BEGIN /*Minor*/

    INSERT INTO #tmp_Data
		 SELECT srecommend
			 , bettype
			 , liveindicator
			 , SUM((winlost - actual_stake) * actualrate) AS                                                                                                   MemberWinLoss
			 , SUM((awinlost + mwinlost + swinlost) * actualrate) AS                                                                                           SMAWinLoss
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
				  END * ISNULL(b.epositiontaking, 0) * actualrate) AS                                                                                                 ExtraPT
			 , SUM(scomm * actualrate) AS                                                                                                                      Commission
			 , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
																		   WHEN tpositiontaking = 1
																		   THEN 0
																		   ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																	    END * ISNULL(b.epositiontaking, 0)) * actualrate) AS                             RealIncome
			 , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
																	WHEN tpositiontaking = 1
																	THEN 0
																	ELSE(winlost - actual_stake) * ISNULL(b.epositiontaking, 0)
																 END) * virtualrate + (scomm - CASE
																							WHEN tpositiontaking = 1
																							THEN 0
																							ELSE b.scomm / (1 - b.tpositiontaking)
																						 END * ISNULL(b.epositiontaking, 0)) * actualrate * CASE
																															   WHEN virtualrate < actualrate
																															   THEN virtualrate / actualrate
																															   ELSE 1
																														    END) AS VirtualIncome
			 , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
																	WHEN tpositiontaking = 1
																	THEN 0
																	ELSE(winlost - actual_stake) * ISNULL(b.epositiontaking, 0)
																 END + CASE
																		 WHEN virtualrate < actualrate
																		 THEN b.scomm - CASE
																						WHEN tpositiontaking = 1
																						THEN 0
																						ELSE b.scomm / (1 - b.tpositiontaking)
																					 END * ISNULL(b.epositiontaking, 0)
																		 ELSE 0
																	  END) * (actualrate - virtualrate)) AS                                      VarianceIncome
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * ABS(b.stake) * CASE
																			   WHEN virtualrate > actualrate
																			   THEN virtualrate
																			   ELSE actualrate
																		    END
				  END) AS                                                                                                                                     RealTurnover
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * ABS(b.stake) * virtualrate
				  END) AS                                                                                                                                     VirtualTurnover
		 FROM dbo.bettrans AS b WITH (NOLOCK)
			INNER JOIN #Match AS m ON b.MatchId = m.MatchId
		 WHERE b.winlostdate = @StartDate
			  AND m.type = CASE
						    WHEN b.BetType = 10
						    THEN 'outright'
						    ELSE 'match'
						END
			  AND b.ruben = 1
			  AND b.statusID IN(111, 112, 113)
		 GROUP BY srecommend
			   , bettype
			   , liveindicator OPTION(RECOMPILE);

    INSERT INTO #Data
		 SELECT sb.IsMajor AS           GroupId
			 , 'Soccer-Minor Bet Types'
			 , CASE
				  WHEN dep.CustId IS NULL
				  THEN 'Credit'
				  ELSE 'Deposit'
			   END AS                  RowName
			 , SUM(MemberWinLoss) AS   MemberWinLoss
			 , SUM(SMAWinLoss) AS      SMAWinLoss
			 , SUM(ExtraPT) AS         ExtraPT
			 , SUM(Commission) AS      Commission
			 , SUM(RealIncome) AS      RealIncome
			 , SUM(VirtualIncome) AS   VirtualIncome
			 , SUM(VarianceIncome) AS  VarianceIncome
			 , SUM(RealTurnover) AS    RealTurnover
			 , SUM(VirtualTurnover) AS VirtualTurnover
		 FROM #tmp_Data AS b
			INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
			LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
		 GROUP BY sb.IsMajor
			   , CASE
				    WHEN dep.CustId IS NULL
				    THEN 'Credit'
				    ELSE 'Deposit'
				END;
END;
BEGIN /*BARM (site only)*/

    INSERT INTO #Data
		 SELECT sb.IsMajor AS                                                                                                                                   GroupId
			 , 'Soccer-Minor Bet Types'
			 , 'BARM' AS                                                                                                                                       RowName
			 , SUM((winlost - actual_stake) * actualrate) AS                                                                                                   MemberWinLoss
			 , SUM((awinlost + mwinlost + swinlost) * actualrate) AS                                                                                           SMAWinLoss
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
				  END * ISNULL(b.epositiontaking, 0) * actualrate) AS                                                                                                 ExtraPT
			 , SUM(scomm * actualrate) AS                                                                                                                      Commission
			 , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
																		   WHEN tpositiontaking = 1
																		   THEN 0
																		   ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																	    END * ISNULL(b.epositiontaking, 0)) * actualrate) AS                             RealIncome
			 , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
																	WHEN tpositiontaking = 1
																	THEN 0
																	ELSE(winlost - actual_stake) * ISNULL(b.epositiontaking, 0)
																 END) * virtualrate + (scomm - CASE
																							WHEN tpositiontaking = 1
																							THEN 0
																							ELSE b.scomm / (1 - b.tpositiontaking)
																						 END * ISNULL(b.epositiontaking, 0)) * actualrate * CASE
																															   WHEN virtualrate < actualrate
																															   THEN virtualrate / actualrate
																															   ELSE 1
																														    END) AS VirtualIncome
			 , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
																	WHEN tpositiontaking = 1
																	THEN 0
																	ELSE(winlost - actual_stake) * ISNULL(b.epositiontaking, 0)
																 END + CASE
																		 WHEN virtualrate < actualrate
																		 THEN b.scomm - CASE
																						WHEN tpositiontaking = 1
																						THEN 0
																						ELSE b.scomm / (1 - b.tpositiontaking)
																					 END * ISNULL(b.epositiontaking, 0)
																		 ELSE 0
																	  END) * (actualrate - virtualrate)) AS                                      VarianceIncome
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * ABS(b.stake) * CASE
																			   WHEN virtualrate > actualrate
																			   THEN virtualrate
																			   ELSE actualrate
																		    END
				  END) AS                                                                                                                                     RealTurnover
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * ABS(b.stake) * virtualrate
				  END) AS                                                                                                                                     VirtualTurnover
		 FROM dbo.bettrans AS b WITH (NOLOCK)
			INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
			INNER JOIN #Match AS m ON b.MatchId = m.MatchId
		 WHERE b.recommend = 5707545
			  AND b.winlostdate = @StartDate
			  AND m.type = CASE
						    WHEN b.BetType = 10
						    THEN 'outright'
						    ELSE 'match'
						END
			  AND b.ruben = 1
			  AND b.statusID IN(111, 112, 113)
		 GROUP BY sb.IsMajor;
/*- set data default for 'Deposit' if there is no data*/

    INSERT INTO #Data(GroupId
				, GroupName
				, RowName
				, MemberWinLoss
				, SMAWinLoss
				, ExtraPT
				, Commission
				, RealIncome
				, VirtualIncome
				, VarianceIncome
				, RealTurnover
				, VirtualTurnover)
		 SELECT GroupId
			 , GroupName
			 , 'Deposit' AS RowName
			 , 0 AS         MemberWinLoss
			 , 0 AS         SMAWinLoss
			 , 0 AS         ExtraPT
			 , 0 AS         Commission
			 , 0 AS         RealIncome
			 , 0 AS         VirtualIncome
			 , 0 AS         VarianceIncome
			 , 0 AS         RealTurnover
			 , 0 AS         VirtualTurnover
		 FROM
			 (
				SELECT GroupId
					, GroupName
				FROM #Data
				WHERE RowName = 'BARM'
				EXCEPT
				SELECT GroupId
					, GroupName
				FROM #Data
				WHERE RowName = 'Deposit'
			 ) AS D;
/*-- Update Credit = Credit - BARM, Deposit = Deposit + BARM*/

    UPDATE c
		 SET
			c.MemberWinLoss = ISNULL(c.MemberWinLoss, 0)+CASE
												    WHEN c.RowName = 'Credit'
												    THEN-ISNULL(d.MemberWinLoss, 0)
												    ELSE ISNULL(d.MemberWinLoss, 0)
												END
		   , c.SMAWinLoss = ISNULL(c.SMAWinLoss, 0)+CASE
											   WHEN c.RowName = 'Credit'
											   THEN-ISNULL(d.SMAWinLoss, 0)
											   ELSE ISNULL(d.SMAWinLoss, 0)
										    END
		   , c.ExtraPT = ISNULL(c.ExtraPT, 0)+CASE
										  WHEN c.RowName = 'Credit'
										  THEN-ISNULL(d.ExtraPT, 0)
										  ELSE ISNULL(d.ExtraPT, 0)
									   END
		   , c.Commission = ISNULL(c.Commission, 0)+CASE
											   WHEN c.RowName = 'Credit'
											   THEN-ISNULL(d.Commission, 0)
											   ELSE ISNULL(d.Commission, 0)
										    END
		   , c.RealIncome = ISNULL(c.RealIncome, 0)+CASE
											   WHEN c.RowName = 'Credit'
											   THEN-ISNULL(d.RealIncome, 0)
											   ELSE ISNULL(d.RealIncome, 0)
										    END
		   , c.VirtualIncome = ISNULL(c.VirtualIncome, 0)+CASE
												    WHEN c.RowName = 'Credit'
												    THEN-ISNULL(d.VirtualIncome, 0)
												    ELSE ISNULL(d.VirtualIncome, 0)
												END
		   , c.VarianceIncome = ISNULL(c.VarianceIncome, 0)+CASE
													 WHEN c.RowName = 'Credit'
													 THEN-ISNULL(d.VarianceIncome, 0)
													 ELSE ISNULL(d.VarianceIncome, 0)
												  END
		   , c.RealTurnover = ISNULL(c.RealTurnover, 0)+CASE
												  WHEN c.RowName = 'Credit'
												  THEN-ISNULL(d.RealTurnover, 0)
												  ELSE ISNULL(d.RealTurnover, 0)
											   END
		   , c.VirtualTurnover = ISNULL(c.VirtualTurnover, 0)+CASE
													   WHEN c.RowName = 'Credit'
													   THEN-ISNULL(d.VirtualTurnover, 0)
													   ELSE ISNULL(d.VirtualTurnover, 0)
												    END
    FROM #Data c
	   FULL JOIN #Data d ON c.GroupId = d.GroupId
					    AND c.GroupName = d.GroupName
					    AND d.RowName = 'BARM'
					    AND c.RowName IN('Credit', 'Deposit');
/*---Delete BARM row used for calculate*/

    DELETE #Data
    WHERE RowName = 'BARM';
END;
BEGIN /* RM   */


    INSERT INTO #Data
		 SELECT 0 AS                                                                                                                                             GroupId
			 , 'RM' AS                                                                                                                                          GroupName
			 , CASE
				  WHEN b.recommend = 52466
				  THEN '8RM Total'
				  WHEN b.recommend = 5707545
				  THEN 'BARM Total'
				  ELSE ''
			   END AS                                                                                                                                           RowName
			 , -SUM((winlost - actual_stake) * actualrate) AS                                                                                                   MemberWinLoss
			 , -SUM((awinlost + mwinlost + swinlost) * actualrate) AS                                                                                           SMAWinLoss
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
				  END * ISNULL(b.epositiontaking, 0) * actualrate) AS                                                                                                  ExtraPT
			 , SUM(scomm * actualrate) AS                                                                                                                       Commission
			 , -SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
																		    WHEN tpositiontaking = 1
																		    THEN 0
																		    ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																		END * ISNULL(b.epositiontaking, 0)) * actualrate) AS                             RealIncome
			 , -SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
																	 WHEN tpositiontaking = 1
																	 THEN 0
																	 ELSE(winlost - actual_stake) * ISNULL(b.epositiontaking, 0)
																  END) * virtualrate + (scomm - CASE
																							 WHEN tpositiontaking = 1
																							 THEN 0
																							 ELSE b.scomm / (1 - b.tpositiontaking)
																						  END * ISNULL(b.epositiontaking, 0)) * actualrate * CASE
																															    WHEN virtualrate < actualrate
																															    THEN virtualrate / actualrate
																															    ELSE 1
																															END) AS VirtualIncome
			 , -SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
																	 WHEN tpositiontaking = 1
																	 THEN 0
																	 ELSE(winlost - actual_stake) * ISNULL(b.epositiontaking, 0)
																  END + CASE
																		  WHEN virtualrate < actualrate
																		  THEN b.scomm - CASE
																						 WHEN tpositiontaking = 1
																						 THEN 0
																						 ELSE b.scomm / (1 - b.tpositiontaking)
																					  END * ISNULL(b.epositiontaking, 0)
																		  ELSE 0
																	   END) * (actualrate - virtualrate)) AS                                      VarianceIncome
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * ABS(b.stake) * CASE
																			   WHEN virtualrate > actualrate
																			   THEN virtualrate
																			   ELSE actualrate
																		    END
				  END) AS                                                                                                                                      RealTurnover
			 , SUM(CASE
					 WHEN tpositiontaking = 1
					 THEN 0
					 ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * ABS(b.stake) * virtualrate
				  END) AS                                                                                                                                      VirtualTurnover
		 FROM dbo.bettrans AS b WITH (NOLOCK)
			INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
			INNER JOIN #Match AS m ON b.MatchId = m.MatchId
		 WHERE b.winlostdate = @StartDate
			  AND m.type = CASE
						    WHEN b.BetType = 10
						    THEN 'outright'
						    ELSE 'match'
						END
			  AND b.ruben = 1
			  AND b.statusID IN(111, 112, 113)
			  AND b.recommend IN(52466, 5707545)
		 GROUP BY CASE
				    WHEN b.recommend = 52466
				    THEN '8RM Total'
				    WHEN b.recommend = 5707545
				    THEN 'BARM Total'
				    ELSE ''
				END;
END;
BEGIN /* Query*/


    SELECT d.GroupId AS         GroupId
	    , d.GroupName AS       GroupName
	    , d.RowName AS         RowName
	    , d.MemberWinLoss AS   MemberWinLoss
	    , d.SMAWinLoss AS      SMAWinLoss
	    , -d.ExtraPT AS        ExtraPT
	    , d.Commission AS      Commission
	    , d.RealIncome AS      RealIncome
	    , d.VirtualIncome AS   VirtualIncome
	    , d.VarianceIncome AS  VarianceIncome
	    , d.RealTurnover AS    RealTurnover
	    , d.VirtualTurnover AS VirtualTurnover
    FROM #Data AS d
    ORDER BY GroupName ASC
		 , RowName;
END;
DROP TABLE #SportBetType;
DROP TABLE #DepositSuper;
DROP TABLE #Data;
DROP TABLE #tmp_Data;
DROP TABLE #Match;
GO
