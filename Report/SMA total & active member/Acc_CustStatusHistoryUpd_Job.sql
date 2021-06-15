/*<info serverAlias="DBRPT-bodb_Report" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE bodb_Report
GO

ALTER PROCEDURE [dbo].[Acc_CustStatusHistoryUpd_Job]
AS

/*
	Created by: Lukas
	Date: 2013.07.19
	Task: record customer status
	DB: DBRPT/bodb_Report
	Original SP:
	
	Revisions:
		20210615@Ned.Le: NAP Report - Change the way to get close/suspend (#156803)
	
	Param's Explanation:
*/

BEGIN

	SET NOCOUNT ON 
	
	-- Declare variables
	DECLARE @maxCustID INT
	
	SELECT @maxCustID = ISNULL(MAX(custid),0)
	FROM CustStatusHistory WITH(NOLOCK)

	-- #tmpcustInfo
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
	SET tmp.reject = CASE WHEN cp.SuspendInfo > 1 THEN 1 ELSE cp.SuspendInfo END,
	    tmp.closed = CASE WHEN cp.CloseInfo > 1 THEN 1 ELSE cp.CloseInfo END
	FROM #tmpcustInfo tmp
	     INNER JOIN bodb02.dbo.CustProductStatus cp (NOLOCK) ON tmp.custid = cp.CustID

	-- check for new customers
	IF EXISTS (	SELECT TOP 1 1 
				FROM #tmpcustInfo
				WHERE custid > @maxCustID
			   )
	BEGIN
		INSERT INTO CustStatusHistory
		SELECT custid, 0, 0, 0
		FROM #tmpcustInfo
		WHERE custid > @maxCustID
	END
	
	/* record yesterday customer status */
	DECLARE @onDay INT,
			@yesterday DATETIME
	
	-- get day record
	SET @yesterday = DATEADD(DAY,-1,GETDATE())   
	
	-- position start: bit 0
	SET @onDay = POWER(2,DAY(@yesterday)-1)      	
	
	IF DATEPART(DAY,@yesterday) =  1  -- when record for 1st day of a month
	BEGIN
		-- archive data of last month
		INSERT INTO CustStatusHistory_bk(custid, enabled, reject,closed, arcdate)
		SELECT custid , enabled, reject, closed, CONVERT(VARCHAR(20),DATEADD(DAY,-1,@yesterday),110)
		FROM CustStatusHistory WITH(NOLOCK)
		WHERE custid <= @maxCustID
		
		-- reset & set yesterday status
		UPDATE csh WITH(ROWLOCK,UPDLOCK)
		SET	reject  = @onDay*c.reject, 
			closed  = @onDay*c.closed,
			enabled = @onDay*c.enabled
		FROM CustStatusHistory csh 
			INNER JOIN #tmpcustInfo c ON csh.custid = c.custid
		WHERE csh.custid <= @maxCustID
	END
	ELSE	-- set yesterday status
	BEGIN
		UPDATE csh WITH(ROWLOCK,UPDLOCK)
		SET	reject  = csh.reject | @onDay*c.reject, 
			closed  = csh.closed | @onDay*c.closed,
			enabled = csh.enabled | @onDay*c.enabled
		FROM CustStatusHistory csh 
			INNER JOIN #tmpcustInfo c ON csh.custid = c.custid
	END	
END
