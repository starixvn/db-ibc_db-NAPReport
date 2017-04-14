Use [bodb_CustomerLog]
GO 

ALTER PROCEDURE [dbo].[Acc_Rpt_CreditMovement]
	@FromDate	DATETIME,  
	@ToDate		DATETIME,   
	@SiteList	VARCHAR(MAX) = '',
	@Amount		BIGINT
AS
/*  Created: 20150311@Sophia  
    Task : Credit Movement Report
    DB: DBLOG/bodb_CustomerLog
   
    Revisions: 
		- 20150602@Sophia: remove unused code

	Param's Explanation:

	Execute String: 

		EXEC Acc_Rpt_CreditMovement @FromDate= '2013-03-15 01:13:15.617', @ToDate ='2015-03-30 04:15:11.127' , @SiteList = 'ALL', @Amount = 30000



*/
BEGIN 
	SET NOCOUNT ON 

	DECLARE @CreditMovement AS TABLE (TransDate DATETIME, ExchangeId INT, Currency VARCHAR(100), Site VARCHAR(10), RoleId TINYINT,
									  srecommend INT, mrecommend INT, recommend INT, CustId INT,
									  SuperName VARCHAR(30), MasterName VARCHAR(30), AgentName VARCHAR(30), CustomerName VARCHAR(30),
									  Amount MONEY, BaseAmount MONEY )

	CREATE TABLE #site (SiteID int, Sitename VARCHAR(30))
	
	IF @SiteList <> 'ALL'
	BEGIN 
		INSERT INTO #site(SiteID, Sitename)
		SELECT	s.siteid, s.site
		FROM	bodb02.dbo.site s WITH(NOLOCK)
		INNER JOIN bodb02.dbo.strSplit(@sitelist,',') t 
				ON s.siteid = CONVERT(INT,t.val)
	END
		
	INSERT INTO @CreditMovement (TransDate, CustId, Amount, BaseAmount )
	SELECT	DATEADD(dd, 1, DATEDIFF(dd, 1, L.LogDate)) AS TransDate, 
			L.CustId, 
			SUM (ISNULL(L.NewValue,0) - ISNULL(L.OldValue,0)) AS Amount, 
			SUM ((ISNULL(L.NewValue,0) -  ISNULL(L.OldValue,0))) * L.ActualRate AS BaseAmount 
	FROM	bodb_CustomerLog.dbo.UserLog_Credit L WITH (NOLOCK)		
	WHERE	L.LogDate BETWEEN @FromDate AND @ToDate		 
			AND ISNULL(L.NewValue,0) > ISNULL(L.OldValue,0)
	GROUP BY DATEADD(dd, 1, DATEDIFF(dd, 1, L.LogDate)),
			L.ActualRate, L.CustId
	HAVING	SUM((ISNULL(L.NewValue,0) - ISNULL(L.OldValue,0))) * L.ActualRate > @Amount
			
 
	UPDATE L
	SET	   ExchangeId = C.Currency, 		
		   srecommend =  C.srecommend,
		   mrecommend =  C.mrecommend,
		   recommend =  C.recommend,
		   CustomerName = CASE WHEN C.RoleID = 1 THEN C.Username END,
		   Site =  C.Site,
		   RoleId = C.RoleId
	FROM   @CreditMovement L
		INNER JOIN bodb02.dbo.Customer C WITH (NOLOCK)  
			ON C.CustID = L.CustID 

	

	UPDATE	L
	SET		Currency = E.Currency,
			SuperName = S.Username,
			MasterName = M.Username,
			AgentName = A.Username,
			Site = CASE WHEN ISNULL(L.Site,'') = '' AND L.RoleID = 1 THEN A.Site ELSE L.Site END
	FROM  @CreditMovement L 
		LEFT JOIN bodb02.dbo.Exchange E WITH (NOLOCK) 
			ON E.ExchangeId = L.ExchangeId
		LEFT JOIN bodb02.dbo.Customer S WITH (NOLOCK)  
			ON S.CustID = L.srecommend AND S.roleid = 4
		LEFT JOIN bodb02.dbo.Customer M WITH (NOLOCK)  
			ON M.CustID = L.mrecommend AND M.roleid = 3
		LEFT JOIN bodb02.dbo.Customer A WITH (NOLOCK)  
			ON A.CustID = L.recommend AND A.roleid = 2 
 

	SELECT * FROM @CreditMovement
	WHERE (Site IN (SELECT SiteName FROM #site) OR @SiteList = 'ALL')
	ORDER BY TransDate, SuperName, MasterName, AgentName, CustomerName
END  


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CreditMovement] TO [bodbAdminNet]
GO