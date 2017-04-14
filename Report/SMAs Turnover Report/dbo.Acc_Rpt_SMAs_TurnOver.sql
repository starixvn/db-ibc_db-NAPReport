CREATE PROCEDURE [dbo].[Acc_Rpt_SMAs_TurnOver]
	@WinlostDate	SMALLDATETIME,
	@MoveBetsDay	SMALLDATETIME,
	@ShowSB			BIT				=	1,
	@ShowRB			BIT				=	1,
	@ShowNG			BIT				=	1,
	@ShowKN			BIT				=	1,
	@ShowLC			BIT				=	1,
	@ShowVS			BIT				=	1,
	@ShowCS			BIT				=	1,
	@ShowGD			BIT				=	1, -- gold deluxe
	@ShowMG			BIT				=	1, -- metrix gaming
	@showMGC 		BIT				=	1, --Micro Gaming
	@ShowOpened		BIT				=	1,
	@ShowClosed		BIT				=	0,
	@ShowSuspended	BIT				=	0
AS  
/*  Created: Dominic  
	Date: 2014-05-22  
    Task : SMA Turnover Report by Date
    DB: DBAGE/bodb02  
   
    Revisions:  
		-20150529@Jim: apply sport&bettype matrix and support GD,MG
		-20150710@Jim:  Microgaming integration (Feature #38168)	
	Param's Explanation:   
	  + @winLostDate: The specified date used as one of the filter criterias
	  + @MoveBetsDay: The day when bets are moved to bettrans14
	  + @ShowSB: Include SportsBook bets
	  + @ShowRB: Include RB bets
	  + @ShowNG: Include Number game bets
	  + @ShowKN: Include Keno
	  + @ShowLC: Include Live Casino
	  + @ShowVS: Include Virtual Sports
	  +	@ShowCS: Include RNG Casino
	  + @ShowGD: Include Gold Deluxe
	  + @ShowMG: Include Metrix Gaming
	  +	@ShowOpened: Include Opened account status
	  +	@ShowClosed: Include closed account status
	  +	@ShowSuspended: Include suspended account status
  
*/  
BEGIN  
	SET NOCOUNT ON  

	--Contain direct account with a little information
	DECLARE @DirectCusts TABLE  (
		CustID INT,
		RoleID TINYINT,
		Currency INT
		)
	DECLARE @DepositDummySuper TABLE  (
		CustID INT
		)
	--Contain direct account with more information	
	DECLARE @DirectCustsAllInfo TABLE  (
		IsAssignedGroup BIT,
		GroupID SMALLINT,
		GroupHeadline NVARCHAR(50),
		CustID INT,
		UserName NVARCHAR(50),
		RoleID TINYINT,
		Currency INT,
		CurrencyName NVARCHAR(50),
		IsSuspend  BIT,
		IsClosed BIT,
		IsEnable BIT
		)	
	--Contain direct account with more information and filtered by account status	
	CREATE TABLE #DirectCustFilterResult(
		IsAssignedGroup BIT,
		GroupID SMALLINT,
		GroupHeadline NVARCHAR(50),
		CustID INT,
		UserName NVARCHAR(50),
		RoleID TINYINT,
		Currency INT,
		CurrencyName NVARCHAR(50),
		IsSuspend  BIT,
		IsClosed BIT,
		IsEnable BIT
		)	
	--Contain direct accounts with turnover	
	CREATE TABLE #TmpFinalResult (
		IsAssignedGroup BIT,
		GroupID SMALLINT,
		GroupHeadline NVARCHAR(50),
		CustID INT,
		UserName NVARCHAR(50),
		RoleID TINYINT,
		Currency INT,
		CurrencyName NVARCHAR(50),
		TurnOverAfterPT MONEY,
		TurnOverAfterPTMYR MONEY,
		TurnOver MONEY,
		TurnOverMYR MONEY
		)
	DECLARE @SportBettype TABLE(ProductID INT,Bettype INT,EventType INT,SubProduct VARCHAR(200))
	INSERT INTO @SportBettype
	EXEC dbo.Acc_SportBettypeMatrix_Sel @mode=5
	DECLARE @tmpbettype AS TABLE (bettype INT)
	
	IF @ShowSB = 1  
	INSERT INTO @tmpbettype(Bettype ) 
	SELECT Bettype    
	 FROM @SportBettype   
	 WHERE ProductID =1 
		AND SubProduct <> 'MG-SuperLive'
IF @ShowRB =1
	INSERT INTO @tmpbettype(Bettype) 
	SELECT Bettype   
	 FROM @SportBettype   
	 WHERE ProductID = 2
	 
IF @ShowNG = 1  
	INSERT INTO @tmpbettype(Bettype ) 
	SELECT Bettype   
	 FROM @SportBettype   
	 WHERE ProductID =3
IF @ShowLC = 1
	INSERT INTO @tmpbettype(Bettype) 
	SELECT Bettype   
	 FROM @SportBettype   
	 WHERE ProductID = 4

IF @ShowCS = 1
	INSERT INTO @tmpbettype(Bettype) 
	SELECT Bettype 
	 FROM @SportBettype   
	 WHERE ProductID = 6
	
IF @showVS = 1
	INSERT INTO @tmpbettype(Bettype ) 
	 SELECT Bettype   
	 FROM @SportBettype   
	 WHERE ProductID = 5	

IF @ShowKN = 1    
	 INSERT INTO @tmpbettype(Bettype )   
	  SELECT Bettype    
	 FROM @SportBettype   
	 WHERE ProductID = 8
IF @ShowGD =1 
	 INSERT INTO @tmpbettype(Bettype )   
	 SELECT Bettype   
	 FROM @SportBettype   
	 WHERE ProductID = 12
 
IF @ShowMG =1 
	INSERT INTO @tmpbettype(Bettype )   
	SELECT Bettype   
	FROM @SportBettype   
	WHERE ProductID = 1
		AND SubProduct= 'MG-SuperLive'	
IF @showMGC =1  --Micro Gaming
	INSERT INTO @tmpbettype(Bettype)   
	SELECT Bettype    
	FROM @SportBettype   
	WHERE ProductID = 13
	
	--Get Super Accounts
	INSERT INTO @DepositDummySuper
	SELECT custid FROM dbo.Dep_CustSuper
	UNION
	SELECT custid FROM dbo.Acc_CustDirect WHERE roleid = 4
	
	INSERT INTO @DirectCusts (
		CustID,
		RoleID,
		Currency
		)
	SELECT
		cust.custid,
		cust.roleid,
		cust.currency
	FROM  dbo.Customer cust WITH(NOLOCK)  
	INNER JOIN dbo.CustSuper cs WITH(NOLOCK) ON cust.custid = cs.custid AND cs.IsInternal = 0	
	WHERE cust.roleid = 4 AND cust.currency NOT IN (20 ,27 , 28)
	AND cust.custid NOT IN (SELECT * FROM @DepositDummySuper)
	UNION ALL --Get Direct Master Accounts
	SELECT 
		cust.custid,
		cust.roleid,
		cust.currency
	FROM dbo.Acc_CustDirect acccust  WITH(NOLOCK)  
	INNER JOIN customer cust WITH(NOLOCK) ON  acccust.custid = cust.srecommEND  AND acccust.roleid = 4 AND cust.roleid = 3   
	INNER JOIN custmaster cm WITH(NOLOCK) ON  cm.custid = cust.custid AND cm.isINTernal = 0 
	WHERE cust.currency NOT IN (20,27,28) 
	AND cust.custid NOT IN (SELECT custid FROM dbo.Acc_CustDirect WHERE roleid = 3)
	UNION ALL --Get Direct Agent Accounts
	SELECT 
		cust.custid,
		cust.roleid,
		cust.currency
	FROM dbo.Acc_CustDirect acccust  WITH(NOLOCK)  
	INNER JOIN customer cust WITH(NOLOCK) ON  acccust.custid = cust.mrecommEND  AND acccust.roleid = 3 AND cust.roleid = 2  
	INNER JOIN custagent ca WITH(NOLOCK) ON  ca.custid = cust.custid AND ca.isINTernal = 0  
	WHERE cust.currency NOT IN (20,27,28)
	AND cust.custid NOT IN (SELECT custid FROM dbo.Acc_CustDirect WHERE roleid = 2)
	UNION ALL
	SELECT --Get Direct Member Accounts
		cust.custid,
		cust.roleid,
		cust.currency
	FROM dbo.Acc_CustDirect acccust  WITH(NOLOCK)  
	INNER JOIN customer cust WITH(NOLOCK) ON  acccust.custid = cust.recommEND  AND acccust.roleid = 2 AND cust.roleid = 1  
	INNER JOIN customer cc WITH(NOLOCK) ON  cust.recommEND  = cc.custid  
	WHERE cust.recommend NOT IN
		( SELECT cag.custid
		 FROM dbo.CustAgent cag WITH(NOLOCK)
		 WHERE cag.IsInternal = 1 )
		  AND cust.currency NOT IN ( 20 , 27 , 28 )
	UNION
	SELECT --Super Consolidated Group
		c.custid,
		c.roleid,
		c.currency
	FROM dbo.custAccount ca 
	INNER JOIN dbo.Customer c ON c.custid = ca.custid
	INNER JOIN dbo.CustSuper cs WITH(NOLOCK) ON c.custid = cs.custid AND cs.IsInternal = 0
	WHERE c.currency NOT IN ( 20 , 27 , 28 ) AND c.roleid = 4
	UNION
	SELECT --Master Consolidated Group
		c.custid,
		c.roleid,
		c.currency
	FROM dbo.custAccount ca 
	INNER JOIN dbo.Customer c ON c.custid = ca.custid
	INNER JOIN dbo.CustMaster cm WITH(NOLOCK) ON c.custid = cm.custid AND cm.IsInternal = 0
	WHERE c.currency NOT IN ( 20 , 27 , 28 ) AND c.roleid = 3
	UNION
	SELECT --Agent Consolidated Group
		c.custid,
		c.roleid,
		c.currency
	FROM dbo.custAccount ca 
	INNER JOIN dbo.Customer c ON c.custid = ca.custid
	INNER JOIN dbo.CustAgent caa WITH(NOLOCK) ON c.custid = caa.custid AND caa.IsInternal = 0
	WHERE c.currency NOT IN ( 20 , 27 , 28 ) AND c.roleid = 2
	UNION
	SELECT --Member Consolidated Group
		c.custid,
		c.roleid,
		c.currency
	FROM dbo.custAccount ca 
	INNER JOIN dbo.Customer c ON c.custid = ca.custid
	WHERE c.recommend NOT IN
		( SELECT cag.custid
		 FROM dbo.CustAgent cag WITH(NOLOCK)
		 WHERE cag.IsInternal = 1 )
		 AND c.currency NOT IN ( 20 , 27 , 28 ) AND c.roleid = 1
	
	--Get more information for direct accounts
	INSERT INTO @DirectCustsAllInfo  
	SELECT  1,c.groupID,cu.username,ca.custID,ci.username,ci.roleid,d.currency,'' currencyname,
		isnull(ci.reject,0) issuspend ,isnull(ci.closed,0) isclosed, ci.[enabled] isEnable
	FROM custaccount ca WITH(NOLOCK)    
	 INNER JOIN custinfo ci WITH(NOLOCK) ON  ci.custid = ca.custid      
	 INNER JOIN @DirectCusts d ON d.custid = ca.custid    
	 LEFT JOIN custaccount c WITH(NOLOCK) ON  c.groupid = ca.groupid  AND c.isgroupheadline = 1 
	 LEFT JOIN custinfo cu WITH(NOLOCK) ON  cu.custid = c.custid
	 WHERE c.groupID <> 0
	 UNION ALL  
	SELECT  0,NULL,'Not assigned to group' , c.custid ,ci.username,ci.roleid,c.currency,'' currencyname,
		isnull(ci.reject,0) issuspend  ,isnull(ci.closed,0) isclosed, ci.[enabled] isEnable
	FROM @DirectCusts c  
	 INNER JOIN custinfo ci WITH(NOLOCK) ON  ci.custid = c.custid   
	WHERE c.custid NOT IN (SELECT  custid FROM custaccount WITH(NOLOCK)) 
	UNION ALL  
	SELECT  0,NULL,'Not assigned to group' , ci.custid ,ci.username,ci.roleid,ci.currency,'' currencyname,
		isnull(ci.reject,0) issuspend  ,isnull(ci.closed,0) isclosed, ci.[enabled] isEnable
	FROM custaccount ca WITH(NOLOCK)   
	INNER JOIN @DirectCusts c ON c.CustID = ca.custid
	INNER JOIN custinfo ci WITH(NOLOCK) ON  ci.custid = ca.custid   
	WHERE ca.groupID = 0

	--Filter direct account with specified status
	IF (@ShowOpened = 1)  
	BEGIN   
	 INSERT INTO #DirectCustFilterResult  
	 SELECT  *   
	 FROM @DirectCustsAllInfo  
	 WHERE issuspend  = 0  AND isclosed = 0  
	END   
	IF (@ShowSuspended = 1)  
	BEGIN   
	 INSERT INTO #DirectCustFilterResult  
	 SELECT  *   
	 FROM @DirectCustsAllInfo  
	 WHERE  issuspend  = 1  AND isclosed = 0    
	END     
	IF (@ShowClosed = 1)  
	BEGIN   
	 INSERT INTO #DirectCustFilterResult  
	 SELECT  *   
	 FROM @DirectCustsAllInfo
	 WHERE isenable = 1  AND isclosed = 1  
	END   

	--Update Currency's name
	UPDATE t
	SET t.currencyname = e.currency
	FROM #DirectCustFilterResult t JOIN Exchange e WITH(NOLOCK) ON e.exchangeid = t.currency
 
	--If the specified day is after the system's movebet day then get data from bettrans table else get data from bettrans14
	IF @WinlostDate > @MoveBetsDay
	BEGIN
		--Calculate TO for Super Agent
		INSERT INTO #TmpFinalResult
		SELECT   
			s.IsAssignedGroup,
			s.GroupID, 
			s.GroupHeadline, 
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName,
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END --liveawayscore is 0 mean Place is refund
				*
				ISNULL(spositiontaking,0)
			) turnoverPT,
			--MYR
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END
				* ISNULL(b.actualrate,0)
				* ISNULL(spositiontaking,0)
			) turnoverMYRPT,
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
			) turnover,
			--MYR
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN  ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
				* ISNULL(b.actualrate,0)
			) turnoverMYR
		FROM #DirectCustFilterResult s
			 JOIN dbo.bettrans b WITH (NOLOCK)  ON s.custid = b.srecommend	
			 INNER JOIN @tmpbettype s ON b.bettype = s.bettype
		WHERE s.RoleID=4 AND b.winlostdate = @WinlostDate AND b.statusID IN (111, 112, 113) 
			
		GROUP BY   
			s.IsAssignedGroup,
			s.GroupID,
			s.GroupHeadline,    
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName
		OPTION (RECOMPILE)			
		--Calculate TO for Direct Master Agent
		INSERT INTO #TmpFinalResult
		SELECT   
			s.IsAssignedGroup,
			s.GroupID,
			s.GroupHeadline,   
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName,
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END --liveawayscore is 0 mean Place is refund
				*
				ISNULL(mpositiontaking,0)
			) turnoverPT,
			--MYR
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END
				* ISNULL(b.actualrate,0)
				* ISNULL(mpositiontaking,0)
			) turnoverMYRPT,
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
			) turnover,
			--MYR
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN  ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
				* ISNULL(b.actualrate,0)
			) turnoverMYR
		FROM #DirectCustFilterResult s
			JOIN dbo.bettrans b WITH (NOLOCK)  ON s.custid = b.mrecommend
			INNER JOIN @tmpbettype s ON b.bettype = s.bettype
		WHERE s.RoleID=3 AND b.winlostdate = @WinlostDate AND b.statusID  IN (111, 112, 113)
		
		GROUP BY   
			s.IsAssignedGroup,
			s.GroupID,
			s.GroupHeadline,   
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName	
		--Calculate TO for Direct Agent
		INSERT INTO #TmpFinalResult
		SELECT   
			s.IsAssignedGroup,
			s.GroupID,  
			s.GroupHeadline, 
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName,
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END --liveawayscore is 0 mean Place is refund
				*
				ISNULL(apositiontaking,0)
			) turnoverPT,
			--MYR
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END
				* ISNULL(b.actualrate,0)
				* ISNULL(apositiontaking,0)
			) turnoverMYRPT,
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
			) turnover,
			--MYR
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN  ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
				* ISNULL(b.actualrate,0)
			) turnoverMYR
		FROM #DirectCustFilterResult s
			JOIN dbo.bettrans b WITH (NOLOCK) ON s.custid = b.recommend
			INNER JOIN @tmpbettype s ON b.bettype = s.bettype
		WHERE 
			s.RoleID=2 AND b.winlostdate = @WinlostDate AND  b.statusID  IN (111, 112, 113)
			 
		GROUP BY   
			s.IsAssignedGroup,
			s.GroupID, 
			s.GroupHeadline,   
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName	
		--Calcualte TO for DIrect Member
		INSERT INTO #TmpFinalResult
		SELECT   
			s.IsAssignedGroup,
			s.GroupID,
			s.GroupHeadline,  
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName,
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END --liveawayscore is 0 mean Place is refund
			) turnoverPT,
			--MYR
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END
				* ISNULL(b.actualrate,0)
			) turnoverMYRPT,
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
			) turnover,
			--MYR
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN  ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
				* ISNULL(b.actualrate,0)
			) turnoverMYR
		FROM #DirectCustFilterResult s
			JOIN dbo.bettrans b WITH (NOLOCK)  ON s.custid = b.custid
			INNER JOIN @tmpbettype s ON b.bettype = s.bettype
		WHERE 
			s.RoleID=1	AND b.winlostdate = @WinlostDate AND b.statusID IN (111, 112, 113)
			
		GROUP BY   
			s.IsAssignedGroup,
			s.GroupID,
			s.GroupHeadline,    
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName		
	END
	ELSE
	BEGIN
		--Calculate TO for Super Agent
		INSERT INTO #TmpFinalResult
		SELECT   
			s.IsAssignedGroup,
			s.GroupID, 
			s.GroupHeadline, 
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName,
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END --liveawayscore is 0 mean Place is refund
				*
				ISNULL(spositiontaking,0)
			) turnoverPT,
			--MYR
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END
				* ISNULL(b.actualrate,0)
				* ISNULL(spositiontaking,0)
			) turnoverMYRPT,
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
			) turnover,
			--MYR
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN  ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
				* ISNULL(b.actualrate,0)
			) turnoverMYR
		FROM #DirectCustFilterResult s
			 JOIN dbo.bettrans14 b WITH (NOLOCK)  ON s.custid = b.srecommend AND s.RoleID=4
			 INNER JOIN @tmpbettype s ON b.bettype = s.bettype
		WHERE b.winlostdate = @WinlostDate AND b.statusID IN (111, 112, 113) 
			
		GROUP BY   
			s.IsAssignedGroup,
			s.GroupID,
			s.GroupHeadline,    
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName
		OPTION (RECOMPILE)			
		--Calculate TO for Direct Master Agent
		INSERT INTO #TmpFinalResult
		SELECT   
			s.IsAssignedGroup,
			s.GroupID,
			s.GroupHeadline,   
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName,
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END --liveawayscore is 0 mean Place is refund
				*
				ISNULL(mpositiontaking,0)
			) turnoverPT,
			--MYR
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END
				* ISNULL(b.actualrate,0)
				* ISNULL(mpositiontaking,0)
			) turnoverMYRPT,
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
			) turnover,
			--MYR
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN  ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
				* ISNULL(b.actualrate,0)
			) turnoverMYR
		FROM #DirectCustFilterResult s
			JOIN dbo.bettrans14 b WITH (NOLOCK)  ON s.custid = b.mrecommend AND s.RoleID=3
			INNER JOIN @tmpbettype s ON b.bettype = s.bettype
		WHERE b.winlostdate = @WinlostDate AND b.statusID  IN (111, 112, 113)
			 
		GROUP BY   
			s.IsAssignedGroup,
			s.GroupID,
			s.GroupHeadline,   
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName	
		--Calculate TO for Direct Agent
		INSERT INTO #TmpFinalResult
		SELECT   
			s.IsAssignedGroup,
			s.GroupID,  
			s.GroupHeadline, 
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName,
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END --liveawayscore is 0 mean Place is refund
				*
				ISNULL(apositiontaking,0)
			) turnoverPT,
			--MYR
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END
				* ISNULL(b.actualrate,0)
				* ISNULL(apositiontaking,0)
			) turnoverMYRPT,
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
			) turnover,
			--MYR
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN  ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
				* ISNULL(b.actualrate,0)
			) turnoverMYR
		FROM #DirectCustFilterResult s
			JOIN dbo.bettrans14 b WITH (NOLOCK) ON s.custid = b.recommend AND s.RoleID=2
			INNER JOIN @tmpbettype s ON b.bettype = s.bettype
		WHERE b.winlostdate = @WinlostDate AND  b.statusID  IN (111, 112, 113)
			
		GROUP BY   
			s.IsAssignedGroup,
			s.GroupID, 
			s.GroupHeadline,   
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName	
		--Calcualte TO for DIrect Member
		INSERT INTO #TmpFinalResult
		SELECT   
			s.IsAssignedGroup,
			s.GroupID,
			s.GroupHeadline,  
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName,
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END --liveawayscore is 0 mean Place is refund
			) turnoverPT,
			--MYR
			SUM(CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END
				* ISNULL(b.actualrate,0)
			) turnoverMYRPT,
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
			) turnover,
			--MYR
			SUM(
				CASE WHEN b.bettype IN (33, 43) AND liveawayscore = 0 THEN  ISNULL(ABS(stake),0)/2 ELSE ISNULL(ABS(stake),0) END 
				* ISNULL(b.actualrate,0)
			) turnoverMYR
		FROM #DirectCustFilterResult s
			JOIN dbo.bettrans14 b WITH (NOLOCK)  ON s.custid = b.custid AND s.RoleID=1
			INNER JOIN @tmpbettype s ON b.bettype = s.bettype
		WHERE b.winlostdate = @WinlostDate AND b.statusID IN (111, 112, 113)
			 
		GROUP BY   
			s.IsAssignedGroup,
			s.GroupID,
			s.GroupHeadline,    
			s.custid,
			s.UserName,
			s.RoleID,
			s.currency, 
			s.CurrencyName	
	END
	
	--Show reported data
	SELECT 
       rs.IsAssignedGroup,
       rs.GroupID,
       rs.GroupHeadline,
       rs.CustID,
       rs.UserName,
       rs.CurrencyName Currency,
       rs.RoleID,
       rs.TurnOverAfterPT,
       rs.TurnOverAfterPTMYR,
       rs.TurnOver MemberTurnOver,
       rs.TurnOverMYR MemberTurnOverMYR
	FROM #TmpFinalResult rs
	WHERE ABS(rs.TurnOver) <> 0 AND ABS(rs.TurnOverAfterPT) <> 0
	ORDER BY rs.IsAssignedGroup ASC,rs.GroupHeadline ASC,rs.TurnOverMYR DESC
		
	--Drop temp tables
	DROP TABLE #DirectCustFilterResult
	DROP TABLE #TmpFinalResult
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_SMAs_TurnOver] TO [bodbAdminNet]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_SMAs_TurnOver] TO vnteam