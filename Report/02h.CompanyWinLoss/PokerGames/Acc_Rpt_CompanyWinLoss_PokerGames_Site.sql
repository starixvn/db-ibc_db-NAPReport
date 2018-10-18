/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb02];
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_PokerGames_Site
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @BetType      INT
   , @Site         VARCHAR(50)
   , @IsLive       INT           = 2
AS
/*
Creator: 20180824@Cherry
Task:  Poker Games Integration - Implement Company Winloss By Products report [#97830]
DB: DBACC/bodb02

Revisions: 	 
	 - 20180831@Kean: Integrate Insurance Of Poker Games (#97830)
	 - 20181018@Robert: Fix performance issue on House Win Loss by Product [#103309]
Parameter's Explanation:
	- @Site: credit, deposit	
	
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_PokerGames_Site] @StartDate='2018-08-21', @EndDate='2018-08-21', @Site = 'Credit', @BetType = 1404

*/

SET NOCOUNT ON;
BEGIN /* #Agent*/


    CREATE TABLE #Agent(
	    CustId    INT
	    PRIMARY KEY
	  , Site      VARCHAR(50));
    IF @Site = 'Deposit'
	   BEGIN
		  INSERT INTO #Agent
			    SELECT c.CustId
				    , Site
			    FROM customer AS c WITH (NOLOCK)
			    WHERE c.RoleID = 2
					AND EXISTS
							 (
								SELECT 1
								FROM Dep_CustSuper AS dep WITH (NOLOCK)
								WHERE c.srecommend = dep.CustId
							 );
	   END;
	   ELSE
	   BEGIN
		  INSERT INTO #Agent
		  SELECT c.CustId
			  , Site
		  FROM customer AS c WITH (NOLOCK)
		  WHERE c.RoleID = 2
			   AND NOT EXISTS
						   (
							  SELECT 1
							  FROM Dep_CustSuper dep WITH (NOLOCK)
							  WHERE c.srecommend = dep.CustId
						   );
	   END;
END;
BEGIN
/*----Get Sport Bettype Matrix------
         Check SP Version	 */

    DECLARE @isTest    BIT = 0;
    SELECT @isTest = dbo.f_CheckSPVersion
		 (@@PROCID);
    DECLARE @ProductID    INT;

    SELECT DISTINCT
		 @ProductID = s.ProductID
    FROM dbo.f_SportBettypeMatrix_Sel
	    (0, 0, 0, 2, '', '', 1) AS s
	   INNER JOIN dbo.SportBettypeMatrix AS t WITH (NOLOCK) ON t.BetType = s.BetType
												    AND t.ProductId = s.ProductId
    WHERE s.bettype = @BetType;
/*- End Sport Bettype Matrix------*/
END;
BEGIN /*-- Extra PT */

    CREATE TABLE #ExtraPT_Sel(
	    SuperID      INT
	  , Sporttype    INT
	  , ExtraPT      DECIMAL(9, 8));
    INSERT INTO #ExtraPT_Sel(SuperID
					  , Sporttype
					  , ExtraPT)
		 SELECT SuperId
			 , a.Sporttype
			 , SUM(ExtraPT) AS ExtraPT
		 FROM bodb02.dbo.Acc_GroupExtraPTSetting AS a WITH (NOLOCK)
		 WHERE @StartDate BETWEEN FromDate AND Todate
			  AND a.ProductId = @ProductID
		 GROUP BY SuperId
			   , a.Sporttype;
/* Extra Comm*/

    CREATE TABLE #ExtraComm_Sel(
	    SuperID      INT
	  , Sporttype    INT
	  , ExtraComm    DECIMAL(9, 8));
    INSERT INTO #ExtraComm_Sel(SuperID
					    , Sporttype
					    , ExtraComm)
		 SELECT SuperId
			 , a.Sporttype
			 , SUM(ExtraCommRate) AS ExtraComm
		 FROM bodb02.dbo.Acc_GroupExtraCommRateSetting AS a WITH (NOLOCK)
		 WHERE @StartDate BETWEEN FromDate AND Todate
			  AND a.ProductId = @ProductID
		 GROUP BY SuperId
			   , a.Sporttype;
END;
BEGIN /* Query*/


    SELECT Site AS                                                                                                                                                                                          RowName
	    , SUM((winlost - actual_stake) * actualrate) AS                                                                                                                                                    MemberWinLoss
	    , SUM((awinlost + mwinlost + swinlost) * actualrate) AS                                                                                                                                            SMAWinLoss
	    , -SUM(((-b.oddsspread) * ISNULL(c.ExtraComm, 0) + (ISNULL(b.transid2, 0) * 1.0 / 10000) * ISNULL(e.ExtraPT, 0)) * actualrate) AS                                                                  ExtraPT
	    , SUM(scomm * actualrate) AS                                                                                                                                                                       Commission
	    , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (-b.oddsspread) * ISNULL(c.ExtraComm, 0) - (ISNULL(b.transid2, 0) * 1.0 / 10000) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome
	    , 0 AS                                                                                                                                                                                             RealTurnover
    FROM bettrans AS b WITH (NOLOCK)
	   INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
	   LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
	   LEFT JOIN #ExtraComm_Sel AS c ON c.SuperID = b.srecommend
    WHERE b.winlostdate = @StartDate
		AND
		    (@IsLive = 2
			OR b.liveindicator = @IsLive)
		AND b.BetType = @BetType
		AND b.ruben = 1
		AND b.statusID IN(111, 112, 113)
    GROUP BY Site
    ORDER BY RowName;
END;
DROP TABLE #Agent;
DROP TABLE #ExtraPT_Sel;
DROP TABLE #ExtraComm_Sel;
GO

GRANT EXECUTE ON dbo.Acc_Rpt_CompanyWinLoss_PokerGames_Site TO [bodbAdminNet];
GO

GRANT VIEW DEFINITION ON dbo.Acc_Rpt_CompanyWinLoss_PokerGames_Site TO [vnteam];
GO