ALTER PROCEDURE [dbo].[Acc_Rpt_RNGCasinoAutomail]  
 @amount MONEY = 5000,  
 @fromdate DATETIME,  
 @todate DATETIME  
   
AS  

 
/* 
 Created: Dom 
 Date: 20140125 
 Task : RNG Casino Automail report 
 DB: DBACC.bodb02 
 Original: 
 
 Revisions: 
   - 20151026@Robert :Feature #41479 phase 2
   - 20160108@Percy: Add new range bettype for Casino [Redmine: #49134]
   - 20160222@Sophia: MBC - RNG Casino need to show by real time [Redmine: #52614]
 Param's Explanation: 
  
*/
-- Get sport bettype
DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT)
INSERT INTO @SportBettype (ProductID , Bettype, EventType )
EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode = 4, @ProductID = 6

DELETE @SportBettype WHERE bettype = 72

CREATE TABLE #temp (Username NVARCHAR(50), recommend INT, transdate DATETIME, winlost_rm MONEY, winlost MONEY )

--- Old Casino 
INSERT INTO #temp (Username,recommend,transdate,winlost_rm, winlost)
SELECT  username,
		recommend,
		transdate,
		SUM((winlost-actual_stake)*actualrate) winlost_rm,
		SUM(winlost-actual_stake) winlost
FROM bettrans (NOLOCK)
WHERE transdate between @FromDate and @ToDate
	AND bettype = 71 
	AND matchid = 0
	AND statusID in (112,113) 
	AND srecommend not in (select custid from Dep_CustSuper(NOLOCK))
GROUP BY username,recommend,transdate
HAVING ABS(SUM((winlost-actual_stake)*actualrate)) >= @amount


--- MBC-RNG Casino
INSERT INTO #temp (Username,recommend,transdate,winlost_rm, winlost )
SELECT  username
       ,recommend
       ,transdate
       ,SUM(( winlost - actual_stake ) * actualrate) winlost_rm
       ,SUM( winlost - actual_stake ) winlost
FROM bettransRNG b WITH (NOLOCK)
INNER JOIN @SportBettype s
	ON b.GameId = s.Bettype 
WHERE transdate BETWEEN @FromDate AND @ToDate
    AND statusID IN (112, 113)
    AND srecommend NOT IN (SELECT custid FROM Dep_CustSuper (NOLOCK))
GROUP BY username
       ,recommend
       ,currency
       ,transdate
HAVING ABS(SUM(( winlost - actual_stake ) * actualrate)) >= @amount

------Get data
SELECT t.username as member
       ,t.transdate
       ,ca.currency
       ,ca.username as agent
       ,SUM(winlost) as winlost
       ,SUM(winlost_rm) as winlost_rm
FROM #temp t
INNER JOIN custInfo(NOLOCK) ca 
	ON ca.custid = t. recommend
GROUP BY  t.username 
       ,t.transdate
       ,ca.currency
       ,ca.username
ORDER BY t.transdate DESC


DROP TABLE #temp
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_RNGCasinoAutomail] TO [bodbAdminNet] AS [dbo]
GO

GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_RNGCasinoAutomail] TO [vnteam] AS [dbo]
GO