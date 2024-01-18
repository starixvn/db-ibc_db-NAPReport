 ALTER PROCEDURE [dbo].[Acc_Rpt_RacingActiveMember]  
 @fromdate datetime,  
 @todate datetime,  
 @BalanceUpDay datetime
AS  
/*  
 Created: Elodie 
 Task : Retrieve Number of Active member for Racing
 DB: DBAGE/bodb02 
 Original: Acc_Rpt_GamesActiveMember
  
 Revisions:      
	- 20130121@Dan: add linked server DBSUM for bodb_Summary
	- 20150529@Jim: apply sport-bettype matrix
   
*/  
  
SET NOCOUNT ON  

CREATE TABLE #tmpcust (CustID INT PRIMARY KEY CLUSTERED)

DECLARE @SportBettype TABLE(ProductID INT,Bettype INT,EventType INT,SubProduct VARCHAR(200))
INSERT INTO @SportBettype
EXEC dbo.Acc_SportBettypeMatrix_Sel @mode=5

IF @Todate >= @BalanceUpDay  
BEGIN  	
	IF @BalanceUpDay < @FromDate   
		SELECT @BalanceUpDay=@FromDate  

	INSERT INTO #tmpcust		
		SELECT DISTINCT custid
		FROM sum_winloss with(NOLOCK) 			
		WHERE roleid = 1 and sporttype = 151
				AND winlostdate BETWEEN @BalanceUpDay AND @Todate				
		
	INSERT INTO #tmpcust
		SELECT DISTINCT custid
		FROM bettrans b WITH(NOLOCK)			
		WHERE winlostdate BETWEEN @fromdate and @todate
			and bettype in (SELECT bettype FROM @SportBettype WHERE ProductID = 2)
			AND NOT EXISTS (SELECT 1 FROM #tmpcust WHERE custid = b.custid)
			 
END  

IF @FromDate < @BalanceUpDay   
BEGIN  
	IF @todate >= DATEADD(dd, -1, @BalanceUpDay)  
	  SELECT @ToDate = DATEADD(dd, -1, @BalanceUpDay)  
    
	INSERT INTO #tmpcust 
		SELECT DISTINCT s.custid
		FROM DBSUM.bodb_Summary.dbo.sum_Winloss_old s WITH (nolock)  			
		WHERE s.roleid = 1 and sporttype = 151		
			AND winlostdate BETWEEN @fromdate AND @ToDate  			
			AND NOT EXISTS(SELECT 1 FROM #tmpcust WHERE custid = s.custid)			
END  

DELETE t
FROM #tmpCust t
	INNER JOIN custInfo ci WITH(NOLOCK) ON t.custid = ci.custid
WHERE roleid = 1 AND currency = 20

SELECT count(1) as TotalActiveMembers
FROM #tmpCust

DROP TABLE #tmpcust

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_RacingActiveMember] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_RacingActiveMember] TO [vnteam]