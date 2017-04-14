ALTER PROCEDURE [dbo].[Acc_Rpt_RNGCasinoAutomail_Recent]
 @amount MONEY = 5000,
 @fromdate DATETIME,
 @todate DATETIME
 
AS

/*
 Created: Robert
 Date: 20151001
 Task :#41479 - Big Win/Loss Members on RnG product
 DB: DBACC.bodb02
 Original:
	
 Revisions:
	-20151015@Robert: revise sp
	- 20160108@Percy: Add new range bettype for Casino [Redmine: #49134]
	- 20160222@Sophia: MBC - RNG Casino need to show by real time [Redmine: #52614]
  
 Param's Explanation:
 
*/
IF ISNULL(@amount,0)=0
	RETURN;
ELSE 
BEGIN

	-- Get sport bettype
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT, EventType INT)
	INSERT INTO @SportBettype (ProductID, Bettype,EventType)
		EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode = 4, @ProductID = 6

	DELETE @SportBettype WHERE bettype = 72
	
	CREATE TABLE #temp (Username NVARCHAR(50), recommend INT, [Truncate] DATETIME, winlost_rm MONEY, winlost MONEY )

	----Old Casino 
	INSERT INTO #temp (Username,recommend,[Truncate],winlost_rm, winlost)
	SELECT	 username,
             recommend,             
             DATEADD( Hour, DATEDIFF(Hour , 0, transdate), 0) AS [Truncate],
             SUM((winlost-actual_stake)*actualrate) AS winlost_rm,
             SUM(winlost-actual_stake) AS winlost			       
    FROM dbo.bettrans WITH (NOLOCK)
    WHERE transdate BETWEEN @FromDate and @ToDate
           AND bettype = 71 
           AND matchid = 0
           AND statusID IN (112,113) 
           AND srecommend NOT IN (SELECT custid FROM dbo.Dep_CustSuper WITH (NOLOCK))
    GROUP BY username
            ,recommend           
            ,DATEADD( Hour, DATEDIFF(Hour , 0, transdate), 0)
    HAVING ABS(SUM((winlost-actual_stake)*actualrate)) >= @amount
		
	--- MBC- RNG Casino 
	INSERT INTO #temp (Username,recommend,[Truncate],winlost_rm, winlost )
	SELECT  username,
			recommend,
			DATEADD( Hour, DATEDIFF(Hour, 0, transdate), 0) AS [Truncate],
			SUM((winlost-actual_stake)*actualrate) AS winlost_rm,
			SUM(winlost-actual_stake) AS winlost
	FROM dbo.bettransRNG b WITH (NOLOCK)
	INNER JOIN @SportBettype s ON b.GameId = s.bettype 
	WHERE transdate BETWEEN @FromDate and @ToDate
		AND statusID IN (112,113) 
		AND srecommend NOT IN (SELECT custid FROM dbo.Dep_CustSuper WITH (NOLOCK))
	GROUP BY username
		,recommend
		,DATEADD( Hour, DATEDIFF(Hour , 0, transdate), 0)
	HAVING ABS(SUM((winlost-actual_stake)*actualrate)) >= @amount


	----Get data
	SELECT  t.username  AS member
			,ca.currency
			,ca.username AS agent
			,SUM(winlost) AS winlost
			,SUM(winlost_rm) AS winlost_rm
			,COUNT(*) AS NumOfMembers
			,[Truncate]
	FROM #temp t
	INNER JOIN dbo.custInfo ca WITH (NOLOCK)  ON ca.custid = t.recommend
	GROUP BY t.username   
			,ca.currency
			,ca.username  			
			,[Truncate]
	ORDER BY [Truncate] DESC

	DROP TABLE #temp
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_RNGCasinoAutomail_Recent] TO [bodbAdminNet] AS [dbo]
GO

GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_RNGCasinoAutomail_Recent] TO [vnteam] AS [dbo]
GO