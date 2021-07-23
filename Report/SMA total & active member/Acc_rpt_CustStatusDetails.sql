/*<info serverAlias="DBRPT-bodb_Report" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE bodb_Report
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CustStatusDetails]
	@fromdate DATETIME,
	@todate DATETIME,
	@sitelist VARCHAR(500),
	@roleid INT,
	@showDetailNew BIT,
	@showDetailReject BIT,
	@showDetailClosed BIT,
	@totalRow INT = 0 OUTPUT,
	@pagesize INT = 1000,
	@pageindex INT = 1
AS

/*
	Created: 20130819@Lukas
	Task : view total SMA And Member Active Report detail
	DB: DBRPT/bodb_report
	
	Revisions:
		20210615@Ned.Le: NAP Report - Change the way to get close/suspend (#156803)
	
	Param's Explanation:	
		@fromdate:         begin date to get data for report
		@todate:           end date to get data for report
		@sitelist:         be used to filter data for report
		@roleid:           show info of SMA [0-All|2-Agent|3-Master|4-Super]
		@showDetailNew:    show info of New Created details table [0-No|1-Yes]
		@showDetailReject: show info of Suspended details table [0-No|1-Yes]
		@showDetailClosed: show info of Closed details table [0-No|1-Yes]
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
		   ISNULL(ci.reject, 0) reject,
		   ISNULL(ci.closed, 0) closed,
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
	SET tmp.reject = CASE WHEN cp.SuspendInfo > 0 THEN 1 ELSE 0 END,
	    tmp.closed = CASE WHEN cp.CloseInfo > 0 THEN 1 ELSE 0 END
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

	CREATE TABLE #result (
							[date] DATETIME, 
							groupID INT, 
							username VARCHAR(30), 
							[status] VARCHAR(10), 
							[site] VARCHAR (20),
							currency VARCHAR(20), 
							position VARCHAR(20), 
							creatdate DATETIME, 
							creator VARCHAR(30)
						 )
	
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
			
	DECLARE @RowStart INT, 
			@RowEnd INT	

	--- show new							
	IF @showDetailNew = 1
	BEGIN		
		INSERT INTO #result ([date], groupID, username, [status], [site], currency, position, creatdate, creator)
		SELECT  c.creatdate
				,ISNULL(ca.groupID,-1)  ---- groupID = 0 already existed
				,c.username		   
			    ,CASE	WHEN ci.[Enabled] = 1 AND ci.closed = 0 AND ci.reject = 0 THEN 'Open'
						WHEN ci.[Enabled] = 1 AND ci.closed = 0 AND ci.reject = 1 THEN 'Suspended'
						WHEN ci.[Enabled] = 1 AND ci.closed = 1 THEN 'Closed'
						WHEN ci.[Enabled] = 0 THEN 'Disabled'
				 END
				,c.site 
			    ,e.currency
			    ,CASE c.roleid	WHEN 2 THEN 'Agent' 
								WHEN 3 THEN 'Master' 
								WHEN 4 THEN 'Super' 
				 END
			    ,c.creatdate
			    ,cr.username
		FROM bodb02.dbo.Customer c WITH(NOLOCK)
			INNER JOIN #tmpcustInfo ci ON ci.custid = c.custid
			LEFT JOIN bodb02.dbo.custAccount ca WITH(NOLOCK) ON ca.custid = c.custid				
			INNER JOIN bodb02.dbo.exchange e WITH(NOLOCK) ON c.currency = e.exchangeid
			LEFT JOIN bodb02.dbo.custInfo cr ON cr.custid = c.creator
		WHERE  c.creatdate BETWEEN @fromdate AND @todate			
				AND c.site IN (SELECT sitename FROM #site)
				AND c.roleid = CASE WHEN @roleid = 0 THEN c.roleid ELSE @roleid END
		--- paging		
		SELECT @totalRow = COUNT(1)
		FROM #result	
		
		IF @pageSize = 0 AND @pageindex = 1
		SELECT @pageSize = @totalRow
		
		SELECT @pageindex = @pageindex - 1, @RowStart = @PageSize * @pageindex + 1, @RowEnd = @RowStart + @PageSize - 1 	
		;WITH rs AS
		(
			SELECT t.date, ISNULL(c.username,'N/A') groupHeadline, t.username, 
					t.[status], t.[site], t.currency, t.position,			
					t.creatdate, t.creator, ROW_NUMBER() OVER (ORDER BY ISNULL(c.username,'N/A') , t.date ) AS rownumber 
			FROM #result t
				LEFT JOIN bodb02.dbo.custAccount ca WITH(NOLOCK) ON ca.groupID = t.groupID AND ca.isGroupHeadline = 1
				LEFT JOIN bodb02.dbo.custInfo c ON c.custid = ca.custid
		)			
		SELECT	rs.date, 
				rs.groupHeadline,
				rs.username, 
				rs.[status],
				rs.[site], 
				rs.currency, 
				rs.position, 
				rs.creatdate, 
				rs.creator
		FROM rs
		WHERE rs.rownumber BETWEEN @RowStart AND @RowEnd
		
		RETURN 
	END
	
	
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
		WHERE c.roleid = CASE WHEN @roleid = 0 THEN c.roleid ELSE @roleid END
	END		
	ELSE
	BEGIN
		-- bug incase of bk only -- add status from custinfo wrong position
		INSERT INTO #customer(custid, roleid, sitename, enabled, closed, reject)
		SELECT	 c.custid
				,c.roleid
				,c.site
				,(ISNULL(csh.enabled,0) | ci.enabled*POWER(@2,DATEPART(DAY,GETDATE())-1))*POWER(@2,32) enabled
				,(ISNULL(csh.closed,0) | ci.closed*POWER(@2,DATEPART(DAY,GETDATE())-1))*POWER(@2,32) closed
				,(ISNULL(csh.reject,0) | ci.reject*POWER(@2,DATEPART(DAY,GETDATE())-1))*POWER(@2,32) reject
		FROM bodb02.dbo.customer c WITH(NOLOCK)
			INNER JOIN #tmpcustInfo ci ON c.custid = ci.custid AND c.site IN (SELECT sitename FROM #site)
			LEFT JOIN custStatusHistory csh WITH(NOLOCK) ON csh.custid = ci.custid 
		WHERE c.roleid = CASE WHEN @roleid = 0 THEN c.roleid ELSE @roleid END
			
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
	
	-- show closed customers
	IF @showDetailClosed = 1
	BEGIN	
		;WITH rs AS
		(
			SELECT				
				 custid
				,sitename AS site
				,CASE WHEN enabled & @dateMask <> 0 THEN 1 ELSE 0 END [Enabled]
				,CASE WHEN 
							(enabled & @dateMask <> 0 AND closed & @dateMask = 0 AND reject & @dateMask <> 0 ) -- is suspended 
							AND
							((CAST(LOG(CASE WHEN (reject&@bitMask)^@bitmask = 0 THEN 1 
										ELSE CASE WHEN (reject&@bitMask)^@bitmask > 4294967295 THEN ((reject&@bitMask)^@bitmask)/POWER(@2,32) 
												  ELSE (reject&@bitMask)^@bitmask END 
									END) /LOG(2) AS INT) + CASE WHEN (reject&@bitMask)^@bitmask > 4294967295 THEN 33 ELSE 1 END
						  ) BETWEEN @f AND @t
						) THEN 1 ELSE 0 
					 END  reject
				,CASE WHEN 
							(enabled & @dateMask <> 0 AND closed & @dateMask <> 0 )
							AND
							((CAST(LOG(CASE WHEN (closed&@bitMask)^@bitMask = 0 THEN 1 
										ELSE CASE WHEN (closed&@bitMask)^@bitMask > 4294967295 THEN ((closed&@bitMask)^@bitMask)/POWER(@2,32)
												  ELSE (closed&@bitMask)^@bitMask END
								   END)/LOG(2) AS INT) + CASE WHEN (closed&@bitMask)^@bitMask > 4294967295 THEN 33 ELSE 1 END
						  ) BETWEEN @f AND @t
						) THEN 1 ELSE 0 
					 END  closed
				,CAST(LOG(CASE WHEN (closed&@bitMask)^@bitMask = 0 THEN 1 
										ELSE CASE WHEN (closed&@bitMask)^@bitMask > 4294967295 THEN ((closed&@bitMask)^@bitMask)/POWER(@2,32)
												  ELSE (closed&@bitMask)^@bitMask END
								   END)/LOG(2) AS INT) + CASE WHEN (closed&@bitMask)^@bitMask > 4294967295 THEN 33 ELSE 1 END AS cdate
			FROM #customer			
		) 		
		INSERT INTO #result ([date], groupID, username, [status], [site], currency, position, creatdate, creator)
		SELECT 
				DATEADD(DAY,cdate-DATEPART(DAY,@maxArcDate),@maxArcDate)
				,ISNULL(ca.groupID,-1)  ---- groupID = 0 already existed
				,c.username		   
				,CASE	WHEN rs.[Enabled] = 1 AND rs.closed = 0 AND rs.reject = 0 THEN 'Open'
						WHEN rs.[Enabled] = 1 AND rs.closed = 0 AND rs.reject = 1 THEN 'Suspended'
						WHEN rs.[Enabled] = 1 AND rs.closed = 1 THEN 'Closed'
						WHEN rs.[Enabled] = 0 THEN 'Disabled'
				 END
				,rs.site 
				,e.currency
				,CASE c.roleid	WHEN 2 THEN 'Agent' 
								WHEN 3 THEN 'Master' 
								WHEN 4 THEN 'Super' 
				 END
				,c.creatdate
				,cr.username
		FROM rs 
			INNER JOIN bodb02.dbo.customer c WITH(NOLOCK) ON rs.custid = c.custid 
			LEFT JOIN bodb02.dbo.custAccount ca WITH(NOLOCK) ON ca.custid = c.custid				
			INNER JOIN bodb02.dbo.exchange e WITH(NOLOCK) ON c.currency = e.exchangeid
			LEFT JOIN bodb02.dbo.custInfo cr ON cr.custid = c.creator
		WHERE rs.closed = 1		
	END
	
	-- show suspended customers
	IF @showDetailReject = 1
	BEGIN	
		;WITH rs AS
		(
			SELECT				
				 custid
				 ,roleid
				,sitename AS site
				--,(CASE WHEN enabled & @dateMask <> 0 AND closed & @dateMask = 0 AND reject & @dateMask = 0 THEN 1 ELSE 0 END) [Enabled]
				,CASE WHEN enabled & @dateMask <> 0 THEN 1 ELSE 0 END [Enabled]
				,(CASE WHEN 
						(enabled & @dateMask <> 0 AND closed & @dateMask = 0 AND reject & @dateMask <> 0 ) -- is suspended 
						AND
						((CAST(LOG(CASE WHEN (reject&@bitMask)^@bitmask = 0 THEN 1 
										ELSE CASE WHEN (reject&@bitMask)^@bitmask > 4294967295 THEN ((reject&@bitMask)^@bitmask)/POWER(@2,32) 
												  ELSE (reject&@bitMask)^@bitmask END 
									END) /LOG(2) AS INT) + CASE WHEN (reject&@bitMask)^@bitmask > 4294967295 THEN 33 ELSE 1 END
						  ) BETWEEN @f AND @t
						) THEN 1 ELSE 0 
				 END ) reject
				,(CASE WHEN 
						(enabled & @dateMask <> 0 AND closed & @dateMask <> 0 )
						AND
						((CAST(LOG(CASE WHEN (closed&@bitMask)^@bitMask = 0 THEN 1 
										ELSE CASE WHEN (closed&@bitMask)^@bitMask > 4294967295 THEN ((closed&@bitMask)^@bitMask)/POWER(@2,32)
												  ELSE (closed&@bitMask)^@bitMask END
								   END)/LOG(2) AS INT) + CASE WHEN (closed&@bitMask)^@bitMask > 4294967295 THEN 33 ELSE 1 END
						  ) BETWEEN @f AND @t
						) THEN 1 ELSE 0 
				 END ) closed
				,CAST(LOG(CASE WHEN (reject&@bitMask)^@bitmask = 0 THEN 1 
										ELSE CASE WHEN (reject&@bitMask)^@bitmask > 4294967295 THEN ((reject&@bitMask)^@bitmask)/POWER(@2,32) 
												  ELSE (reject&@bitMask)^@bitmask END 
									END) /LOG(2) AS INT) + CASE WHEN (reject&@bitMask)^@bitmask > 4294967295 THEN 33 ELSE 1 END AS rdate
			FROM #customer
		) 

		INSERT INTO #result ([date], groupID, username, [status], [site], currency, position, creatdate, creator)
		SELECT 	
				DATEADD(DAY,rdate-DATEPART(DAY,@maxArcDate),@maxArcDate)
				,ISNULL(ca.groupID,-1)  ---- groupID = 0 already existed
				,c.username		   
				,CASE	WHEN rs.[Enabled] = 1 AND rs.closed = 0 AND rs.reject = 0 THEN 'Open'
						WHEN rs.[Enabled] = 1 AND rs.closed = 0 AND rs.reject = 1 THEN 'Suspended'
						WHEN rs.[Enabled] = 1 AND rs.closed = 1 THEN 'Closed'
						WHEN rs.[Enabled] = 0 THEN 'Disabled'
				 END
				,rs.site 
				,e.currency
				,CASE c.roleid	WHEN 2 THEN 'Agent' 
								WHEN 3 THEN 'Master' 
								WHEN 4 THEN 'Super' 
				 END
				,c.creatdate
				,cr.username

		FROM rs 
			INNER JOIN bodb02.dbo.customer c WITH(NOLOCK) ON rs.custid = c.custid 
			LEFT JOIN bodb02.dbo.custAccount ca WITH(NOLOCK) ON ca.custid = rs.custid				
			INNER JOIN bodb02.dbo.exchange e WITH(NOLOCK) ON c.currency = e.exchangeid
			LEFT JOIN bodb02.dbo.custInfo cr ON cr.custid = c.creator
		WHERE rs.reject = 1
	END
	
	
	--- paging		
	SELECT @totalRow = COUNT(1)
	FROM #result
		
	IF @pageSize = 0 AND @pageindex = 1
		SELECT @pageSize = @totalRow
	
	SELECT @pageindex = @pageindex - 1, @RowStart = @PageSize * @pageindex + 1, @RowEnd = @RowStart + @PageSize - 1 	
	;WITH rs AS
	(
		SELECT t.date, ISNULL(c.username,'N/A') groupHeadline, t.username, ci.custid,
				t.[status], t.[site], t.currency, t.position,			
				t.creatdate, t.creator, ROW_NUMBER() OVER (ORDER BY ISNULL(c.username,'N/A'),  t.date ) AS rownumber 
		FROM #result t
			inner join #tmpcustInfo ci on t.username = ci.username
			LEFT JOIN bodb02.dbo.custAccount ca WITH(NOLOCK) ON ca.groupID = t.groupID AND ca.isGroupHeadline = 1
			LEFT JOIN bodb02.dbo.custInfo c ON c.custid = ca.custid

	)			
	SELECT	rs.date, 
			rs.groupHeadline,
			rs.username, custid,
			rs.[status],
			rs.[site], 
			rs.currency, 
			rs.position, 
			rs.creatdate, 
			rs.creator
	FROM rs
	WHERE rs.rownumber BETWEEN @RowStart AND @RowEnd

END
GO