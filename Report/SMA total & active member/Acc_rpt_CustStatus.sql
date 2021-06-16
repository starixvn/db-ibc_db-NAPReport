/*<info serverAlias="DBRPT-bodb_Report" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE bodb_Report
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CustStatus]
	@fromdate DATETIME,
	@todate DATETIME,
	@sitelist VARCHAR(500)
AS

/*
	Date: 20130808@Lukas
	Task : Total SMA And Member Active Report
	DB: DBRPT/bodb_report
	
	Revisions:
		20210615@Ned.Le: NAP Report - Change the way to get close/suspend (#156803)
	
	Param's Explanation:
		@fromdate: begin date to get data for report
		@todate:   end date to get data for report
		@sitelist: be used to filter data for report
	
	Example:
		EXEC bodb_Report.dbo.Acc_Rpt_CustStatus '20210601', '20210605', '1,2,3,4'
*/

BEGIN

	SET NOCOUNT ON

	--------------------------
	-- BEGIN - #tmpcustInfo --

	CREATE TABLE #tmpcustInfo (
		custid     INT,
		username   NVARCHAR(50),
		currency   INT,
		roleid     TINYINT,
		srecommend INT,
		reject     BIT,
		closed     BIT,
		Enabled    BIT
	)

	INSERT INTO #tmpcustInfo (custid, username, currency, roleid, srecommend, reject, closed, Enabled)
	SELECT ci.custid,
	       ci.username,
	       ci.currency,
		   ci.roleid,
		   ci.srecommend,
		   ci.reject,
		   ci.closed,
		   ci.Enabled
	FROM bodb02.dbo.custInfo ci (NOLOCK)
	WHERE roleid IN (2, 3, 4)
	      AND NOT EXISTS (SELECT TOP 1 1
	                      FROM bodb02.dbo.Dep_CustSuper cs (NOLOCK)
					      WHERE cs.custid = ci.srecommend)
	
	CREATE CLUSTERED INDEX CIX_tmpcustInfo ON #tmpcustInfo(custid)
	CREATE NONCLUSTERED INDEX IX_tmpcustInfo_username ON #tmpcustInfo(username)
	CREATE NONCLUSTERED INDEX IX_tmpcustInfo_currency ON #tmpcustInfo(currency)
	CREATE NONCLUSTERED INDEX IX_tmpcustInfo_srecommend ON #tmpcustInfo(srecommend)

	UPDATE tmp
	SET tmp.reject = CASE WHEN cp.SuspendInfo >= 1 THEN 1 ELSE 0 END,
	    tmp.closed = CASE WHEN cp.CloseInfo >= 1 THEN 1 ELSE 0 END
	FROM #tmpcustInfo tmp
	     INNER JOIN bodb02.dbo.CustProductStatus cp (NOLOCK) ON tmp.custid = cp.CustID

	-- END - #tmpcustInfo --
	------------------------
	
	IF @fromdate > @todate
		RETURN
	IF @todate > GETDATE()
		SET @todate = GETDATE()
		
	SELECT	@fromdate = CONVERT(datetime,CONVERT(NVARCHAR(20),@fromdate, 23)+ ' 00:00:00'), 
			@todate =  CONVERT(datetime,CONVERT(NVARCHAR(20),@todate, 23)+ ' 23:59:59.997')
	
	CREATE TABLE #site (siteID int, sitename VARCHAR(30))
	INSERT INTO #site(siteID, sitename)
	SELECT s.siteid, s.site
	FROM bodb02.dbo.site s WITH(NOLOCK)
		INNER JOIN bodb02.dbo.strSplit(@sitelist,',') t ON s.siteid = CONVERT(INT,t.val)
	
	DECLARE @maxArcDate DATETIME			

	DECLARE @bigint BIGINT,
			@bit	BIT,
			@2		BIGINT,
			@bitMask BIGINT,
			@dateMask BIGINT

	SELECT	@maxArcDate = MAX(arcDate),
			@bigint = 0,
			@bit	= 0,
			@2		= 2
	FROM custstatusHistory_bk WITH(NOLOCK)
	
	CREATE TABLE #customer(custid INT PRIMARY KEY, roleid INT, closed BIGINT, reject BIGINT, enabled BIGINT, sitename VARCHAR(30))


	IF DATEPART(DAY,GETDATE()) = 1
	BEGIN
		
		INSERT INTO #customer(custid, roleid, sitename, enabled, closed, reject)
		SELECT	 c.custid
				,c.roleid
				,c.site
				,ISNULL(csh.enabled,0)*POWER(@2,1) | @bigint | ci.enabled*POWER(@2,32) enabled
				,ISNULL(csh.closed,0)*POWER(@2,1)  | @bigint | ci.closed*POWER(@2,32) closed
				,ISNULL(csh.reject,0)*POWER(@2,1)  | @bigint | ci.reject*POWER(@2,32) reject
		FROM bodb02.dbo.customer c WITH(NOLOCK)
			INNER JOIN #tmpcustInfo ci ON c.custid = ci.custid AND c.site IN (SELECT sitename FROM #site)
			LEFT JOIN custStatusHistory csh WITH(NOLOCK) ON csh.custid = ci.custid 
			INNER JOIN bodb02.dbo.exchange e WITH(NOLOCK) on e.exchangeid = c.currency
		WHERE c.roleid BETWEEN 2 AND 4
	END		
	ELSE
	BEGIN
		
		INSERT INTO #customer(custid, roleid, sitename, enabled, closed, reject)
		SELECT	 c.custid
				,c.roleid
				,c.site
				,(ISNULL(csh.enabled,0) | ci.enabled*POWER(@2,DATEPART(DAY,GETDATE())-1))*POWER(@2,32) enabled
				,(ISNULL(csh.closed,0) | ci.closed*POWER(@2,DATEPART(DAY,GETDATE())-1))*POWER(@2,32) closed
				,(ISNULL(csh.reject,0) | ci.reject*POWER(@2,DATEPART(DAY,GETDATE())-1))*POWER(@2,32) reject
		FROM bodb02.dbo.customer c WITH(NOLOCK)
			INNER JOIN #tmpcustInfo ci ON c.custid = ci.custid AND c.site IN (SELECT sitename FROM #site)
			INNER JOIN bodb02.dbo.exchange e WITH(NOLOCK) on e.exchangeid = c.currency
			LEFT JOIN custStatusHistory csh WITH(NOLOCK) ON csh.custid = ci.custid 
		WHERE c.roleid BETWEEN 2 AND 4
			
		IF @fromdate <= DATEADD(DAY,1,@maxArcDate)
		BEGIN
			UPDATE c
			SET	 c.enabled = c.enabled | csb.enabled*POWER(@2,1)
				,c.closed =  c.closed  | csb.closed*POWER(@2,1)
				,c.reject =  c.reject  | csb.reject*POWER(@2,1)
			FROM #customer c 
				INNER JOIN custStatusHistory_bk csb WITH(NOLOCK) ON c.custid = csb.custid AND csb.arcDate = @maxArcDate
		END			
		IF DATEPART(DAY,@fromdate) = 1 AND @fromdate < @maxArcDate
		BEGIN
			UPDATE t
			SET t.closed	= t.closed | CASE WHEN ISNULL(csb.closed,0) & POWER(@2,DATEPART(DAY,DATEADD(MONTH,-1,@maxArcDate))-1) = 0 THEN 0 ELSE 1 END
				,t.reject	= t.reject | CASE WHEN ISNULL(csb.reject,0) & POWER(@2,DATEPART(DAY,DATEADD(MONTH,-1,@maxArcDate))-1) = 0 THEN 0 ELSE 1 END
				,t.enabled	= t.enabled | CASE WHEN ISNULL(csb.enabled,0) & POWER(@2,DATEPART(DAY,DATEADD(MONTH,-1,@maxArcDate))-1) = 0 THEN 0 ELSE 1 END
			FROM #customer t 
				INNER JOIN custStatusHistory_bk csb WITH(NOLOCK) ON csb.custid = t.custid AND csb.arcDate = DATEADD(MONTH,-1,@maxArcDate)			
		END
		
	END	
	
	DECLARE @t INT, @f INT
	IF @todate >= DATEADD(DAY,1,@maxArcDate)
	BEGIN
		SELECT	@dateMask = POWER(@2,32+DATEPART(DAY,@todate)-1),
				@t = DATEPART(DAY,@todate) + 31
		IF DATEPART(DAY,@todate) = 31
			SET @bitMask = -1-POWER(-@2,63)
		ELSE
			SET  @bitMask = 2*POWER(@2,32+DATEPART(DAY,@todate)-1) - 1	
	END
	ELSE
	BEGIN
		SELECT  @bitMask = 2*POWER(@2,DATEPART(DAY,@todate)) - 1,
				@dateMask = POWER(@2,DATEPART(DAY,@todate))	,
				@t = DATEPART(DAY,@todate) 
	END
	
	IF @fromdate <= @maxArcDate
		SET @f = DATEPART(DAY,@fromdate)
	ELSE 
		SET @f = DATEPART(DAY,@fromdate) + 31

	IF DATEPART(DAY,@maxArcDate) = 28
		SET @bitMask = @bitMask & CAST(9223372033096679423 AS BIGINT)
	ELSE IF DATEPART(DAY,@maxArcDate) = 29
		SET @bitMask = @bitMask & CAST(9223372033633550335 AS BIGINT)
	ELSE IF DATEPART(DAY,@maxArcDate) = 30
		SET @bitMask = @bitMask & CAST(9223372034707292159 AS BIGINT)

	SELECT	roleid, sitename
			,SUM(CASE WHEN enabled & @dateMask <> 0 AND closed & @dateMask = 0 AND reject & @dateMask = 0 THEN 1 ELSE 0 END) ActiveCnt
			,SUM(CASE WHEN 
						(enabled & @dateMask <> 0 AND closed & @dateMask = 0 AND reject & @dateMask <> 0 ) -- is suspended 
						AND
						((CAST(LOG(CASE WHEN (reject&@bitMask)^@bitmask = 0 THEN 1 
										ELSE CASE WHEN (reject&@bitMask)^@bitmask > 4294967295 THEN ((reject&@bitMask)^@bitmask)/POWER(@2,32) 
												  ELSE (reject&@bitMask)^@bitmask END 
									END) /LOG(2) AS INT) + CASE WHEN (reject&@bitMask)^@bitmask > 4294967295 THEN 33 ELSE 1 END
						  ) BETWEEN @f AND @t
						) THEN 1 ELSE 0 
				 END ) SuspendedCnt
			,SUM(CASE WHEN 
						(enabled & @dateMask <> 0 AND closed & @dateMask <> 0 )
						AND
						((CAST(LOG(CASE WHEN (closed&@bitMask)^@bitMask = 0 THEN 1 
										ELSE CASE WHEN (closed&@bitMask)^@bitMask > 4294967295 THEN ((closed&@bitMask)^@bitMask)/POWER(@2,32)
												  ELSE (closed&@bitMask)^@bitMask END
								   END)/LOG(2) AS INT) + CASE WHEN (closed&@bitMask)^@bitMask > 4294967295 THEN 33 ELSE 1 END
						  ) BETWEEN @f AND @t
						) THEN 1 ELSE 0 
				 END ) ClosedCnt
			INTO #result
	FROM #customer
	GROUP BY roleid, sitename

	;WITH rs AS
	(
		SELECT ISNULL(SUM(CASE c.roleid WHEN 4 THEN 1 ELSE 0 END),0) NewCreatedSuper,
			   ISNULL(SUM(CASE c.roleid WHEN 3 THEN 1 ELSE 0 END),0) NewCreatedMaster,
			   ISNULL(SUM(CASE c.roleid WHEN 2 THEN 1 ELSE 0 END),0) NewCreatedAgent
		FROM bodb02.dbo.Customer c WITH(NOLOCK)
		INNER JOIN bodb02.dbo.exchange e WITH(NOLOCK) on e.exchangeid = c.currency
		WHERE 
			creatdate BETWEEN @fromdate AND @todate
			AND c.roleid IN (2,3,4)
			AND c.site IN (SELECT sitename FROM #site)
	),
	rs2 AS
	(
		SELECT	 SUM(CASE WHEN roleid = 2 THEN ActiveCnt ELSE 0 END) ActiveAgent
				,SUM(CASE WHEN roleid = 3 THEN ActiveCnt ELSE 0 END) ActiveMaster
				,SUM(CASE WHEN roleid = 4 THEN ActiveCnt ELSE 0 END) ActiveSuper
				
				,SUM(CASE WHEN roleid = 2 THEN suspendedCnt ELSE 0 END) SuspendedAgent
				,SUM(CASE WHEN roleid = 3 THEN suspendedCnt ELSE 0 END) SuspendedMaster 
				,SUM(CASE WHEN roleid = 4 THEN suspendedCnt ELSE 0 END) SuspendedSuper
				
				,SUM(CASE WHEN roleid = 2 THEN ClosedCnt ELSE 0 END) ClosedAgent
				,SUM(CASE WHEN roleid = 3 THEN ClosedCnt ELSE 0 END) ClosedMaster
				,SUM(CASE WHEN roleid = 4 THEN ClosedCnt ELSE 0 END) ClosedSuper
		FROM #result		
	)
	SELECT rs.*, rs2.*
	FROM rs CROSS JOIN rs2 
	
	;WITH rs AS
	(
		SELECT	s.siteid, r.sitename
				,SUM(CASE WHEN roleid = 4 THEN ActiveCnt ELSE 0 END) super
				,SUM(CASE WHEN roleid = 3 THEN ActiveCnt ELSE 0 END) master 
				,SUM(CASE WHEN roleid = 2 THEN ActiveCnt ELSE 0 END) agent
		FROM #result r
			INNER JOIN bodb02.dbo.site s WITH(NOLOCK) ON r.sitename = s.site
		GROUP BY s.siteid, r.sitename
	) 
	SELECT siteid ID, sitename, 
			CONVERT(VARCHAR(10),super) + '/' + CONVERT(VARCHAR(10),master) + '/' + CONVERT(VARCHAR(10),agent) AS SMA
	FROM rs
	
END
GO