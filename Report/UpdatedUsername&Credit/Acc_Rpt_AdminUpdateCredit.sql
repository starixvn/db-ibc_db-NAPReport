/*<info serverAlias="DBLOG-bodb_CustomerLog" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_AdminUpdateCredit]
	@Username VARCHAR(50) = '',
	@FromDate	DATETIME,
	@ToDate		DATETIME
AS
/*  Created: Kean  
	Date: 2017-09-15  
    Task : View log admin update credit (#83033),
    DB: DBLOG/bodb_CustomerLog
   
    Revisions: 
		- 20181003@Helen: Get Code from PRO + HOTFIX alias should be DBPOL instead of DBONUSER  [Redmine:102596]
		- 20190405@Patrick: Support archive date range [Redmine: #111476]
    
    Param's Explanation:
		 @Username:  member's username
		 @FromDate, @ToDate: date range
  Example: exec Acc_Rpt_AdminUpdateCredit @username = '', @FromDate = '2017-09-12 00:00:00.000', @ToDate = '2017-09-16 00:00:00.000';
*/  
BEGIN
	SET NOCOUNT ON

	DECLARE @CustID INT
	 
--Contain temporary table
	IF OBJECT_ID('tempdb..#NAPadmin') IS NOT NULL
	BEGIN
		DROP TABLE #NAPadmin
	END

	CREATE TABLE #NAPadmin (
		custid INT PRIMARY KEY,
		username VARCHAR(30),
		groupname NVARCHAR(100) )

-- #CustGroup
	IF OBJECT_ID('tempdb..#CustGroup') IS NOT NULL
	BEGIN
		DROP TABLE #CustGroup
	END

	CREATE TABLE #CustGroup (
		custid INT,
		groupid INT,
		username VARCHAR(30)
		)

	IF @Username <> ''
		BEGIN
			SELECT @CustID = custid
			FROM bodb02.dbo.Customer WITH (NOLOCK)
			WHERE username = @Username 
		END

	-- Admin Group
	SELECT * 
	INTO #AdminGroup
	FROM bodb02.dbo.customer (NOLOCK)
	WHERE roleid > 4

	-- NAPadmin user
	INSERT INTO #NAPadmin (custid, username, groupname)
	SELECT t.custid, t.username, g.GroupName
	FROM #AdminGroup t
		LEFT JOIN DBPOL.NAP_userControl.dbo.acccustomer a WITH (NOLOCK) ON t.custid = a.custid
		LEFT JOIN DBPOL.NAP_userControl.dbo.Acc_groupInfo g WITH (NOLOCK) ON a.groupID = g.groupID AND g.groupname NOT LIKE 'acc%' 
	WHERE g.groupname IS NOT NULL

	-- Customer with group
	INSERT INTO #CustGroup (custid, groupid, username)
	SELECT aa.custid, aa.groupid , bb.username
	FROM bodb02.dbo.custAccount aa WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Customer bb WITH (NOLOCK) ON aa.custid = bb.custid
	WHERE aa.isgroupheadline = 1

	DECLARE @__archiveDate DATETIME
	SELECT @__archiveDate = DATEADD(DAY, 1, dbo.f_CustomerLog_GetArchiveDate())

	IF @FromDate >= @__archiveDate
	BEGIN
		-- Result --> active range
		SELECT  DATEPART(year,ul.logdate) Year, DATEPART(month,ul.logdate) Month, ul.logdate [LogDate],
				na.groupname Department, na.username Admin, c.username [Username], 
				CASE c.roleid WHEN 4 THEN 'Super'
							  WHEN 3 THEN 'Master'
							  WHEN 2 THEN 'Agent'
							  WHEN 1 THEN 'Member'
				ELSE '' END Level,
				ISNULL(shl.username,ISNULL(mhl.username,ISNULL(ahl.username,hl.username))) AS Headline
				, CASE WHEN c.roleid < 4 THEN s.username  
					 ELSE NULL END Super
				,CASE WHEN c.roleid < 3 THEN m.username
					 ELSE NULL END Master 
				, CASE WHEN c.roleid < 2 THEN  a.username 
					 ELSE NULL END Agent
				,case when ul.OldValue IS NULL then 0 else ul.OldValue end OldValue, 
				ul.NewValue, ul.doing Remark
		FROM bodb_CustomerLog.dbo.UserLog_Credit ul WITH (NOLOCK)
			INNER JOIN  #NAPadmin AS na  ON ul.userid = na.custid
			INNER JOIN bodb02.dbo.Customer c with (Nolock) ON ul.custid = c.custid
			LEFT JOIN bodb02.dbo.Customer a WITH(NOLOCK) ON c.recommend = a.custid
			LEFT JOIN bodb02.dbo.Customer m WITH(NOLOCK) ON c.mrecommend = m.custid
			LEFT JOIN bodb02.dbo.Customer s WITH(NOLOCK) ON c.srecommend = s.custid
			LEFT JOIN bodb02.dbo.custAccount ca WITH (NOLOCK) ON ca.custid = c.custid
			LEFT JOIN bodb02.dbo.custAccount sca WITH (NOLOCK) ON sca.custid = c.srecommend
			LEFT JOIN bodb02.dbo.custAccount mca WITH (NOLOCK) ON mca.custid = c.mrecommend
			LEFT JOIN bodb02.dbo.custAccount aca WITH (NOLOCK) ON aca.custid = c.recommend
			LEFT JOIN #CustGroup shl ON shl.groupid = sca.groupid 
			LEFT JOIN #CustGroup mhl ON mhl.groupid = mca.groupid 
			LEFT JOIN #CustGroup ahl ON ahl.groupid = aca.groupid 
			LEFT JOIN #CustGroup hl  ON hl.groupid = ca.groupid 
		WHERE  ul.logdate >= @FromDate AND ul.logdate < DATEADD(d,1,@ToDate) 
			AND ISNULL(ul.OldValue,0) <> ISNULL(ul.NewValue,0) AND (@Username = '' OR  ul.custid = @CustID)
			AND c.currency NOT IN (20,27,28)
		ORDER BY ul.logdate ASC
	END
	IF @ToDate < @__archiveDate
	BEGIN
		-- Result --> archive range
		SELECT  DATEPART(year,ul.logdate) Year, DATEPART(month,ul.logdate) Month, ul.logdate [LogDate],
				na.groupname Department, na.username Admin, c.username [Username], 
				CASE c.roleid WHEN 4 THEN 'Super'
							  WHEN 3 THEN 'Master'
							  WHEN 2 THEN 'Agent'
							  WHEN 1 THEN 'Member'
				ELSE '' END Level,
				ISNULL(shl.username,ISNULL(mhl.username,ISNULL(ahl.username,hl.username))) AS Headline
				, CASE WHEN c.roleid < 4 THEN s.username  
					 ELSE NULL END Super
				,CASE WHEN c.roleid < 3 THEN m.username
					 ELSE NULL END Master 
				, CASE WHEN c.roleid < 2 THEN  a.username 
					 ELSE NULL END Agent
				,case when ul.OldValue IS NULL then 0 else ul.OldValue end OldValue, 
				ul.NewValue, ul.doing Remark
		FROM bodb_CustomerLog_Archive.dbo.UserLog_Credit ul WITH (NOLOCK)
			INNER JOIN  #NAPadmin AS na  ON ul.userid = na.custid
			INNER JOIN bodb02.dbo.Customer c with (Nolock) ON ul.custid = c.custid
			LEFT JOIN bodb02.dbo.Customer a WITH(NOLOCK) ON c.recommend = a.custid
			LEFT JOIN bodb02.dbo.Customer m WITH(NOLOCK) ON c.mrecommend = m.custid
			LEFT JOIN bodb02.dbo.Customer s WITH(NOLOCK) ON c.srecommend = s.custid
			LEFT JOIN bodb02.dbo.custAccount ca WITH (NOLOCK) ON ca.custid = c.custid
			LEFT JOIN bodb02.dbo.custAccount sca WITH (NOLOCK) ON sca.custid = c.srecommend
			LEFT JOIN bodb02.dbo.custAccount mca WITH (NOLOCK) ON mca.custid = c.mrecommend
			LEFT JOIN bodb02.dbo.custAccount aca WITH (NOLOCK) ON aca.custid = c.recommend
			LEFT JOIN #CustGroup shl ON shl.groupid = sca.groupid 
			LEFT JOIN #CustGroup mhl ON mhl.groupid = mca.groupid 
			LEFT JOIN #CustGroup ahl ON ahl.groupid = aca.groupid 
			LEFT JOIN #CustGroup hl  ON hl.groupid = ca.groupid 
		WHERE  ul.logdate >= @FromDate AND ul.logdate < DATEADD(d,1,@ToDate) 
			AND ISNULL(ul.OldValue,0) <> ISNULL(ul.NewValue,0) AND (@Username = '' OR  ul.custid = @CustID)
			AND c.currency NOT IN (20,27,28)
		ORDER BY ul.logdate ASC
	END
	ELSE
	BEGIN
		-- Result -- active range
		SELECT  DATEPART(year,ul.logdate) Year, DATEPART(month,ul.logdate) Month, ul.logdate [LogDate],
				na.groupname Department, na.username Admin, c.username [Username], 
				CASE c.roleid WHEN 4 THEN 'Super'
							  WHEN 3 THEN 'Master'
							  WHEN 2 THEN 'Agent'
							  WHEN 1 THEN 'Member'
				ELSE '' END Level,
				ISNULL(shl.username,ISNULL(mhl.username,ISNULL(ahl.username,hl.username))) AS Headline
				, CASE WHEN c.roleid < 4 THEN s.username  
					 ELSE NULL END Super
				,CASE WHEN c.roleid < 3 THEN m.username
					 ELSE NULL END Master 
				, CASE WHEN c.roleid < 2 THEN  a.username 
					 ELSE NULL END Agent
				,case when ul.OldValue IS NULL then 0 else ul.OldValue end OldValue, 
				ul.NewValue, ul.doing Remark
		FROM bodb_CustomerLog.dbo.UserLog_Credit ul WITH (NOLOCK)
			INNER JOIN  #NAPadmin AS na  ON ul.userid = na.custid
			INNER JOIN bodb02.dbo.Customer c with (Nolock) ON ul.custid = c.custid
			LEFT JOIN bodb02.dbo.Customer a WITH(NOLOCK) ON c.recommend = a.custid
			LEFT JOIN bodb02.dbo.Customer m WITH(NOLOCK) ON c.mrecommend = m.custid
			LEFT JOIN bodb02.dbo.Customer s WITH(NOLOCK) ON c.srecommend = s.custid
			LEFT JOIN bodb02.dbo.custAccount ca WITH (NOLOCK) ON ca.custid = c.custid
			LEFT JOIN bodb02.dbo.custAccount sca WITH (NOLOCK) ON sca.custid = c.srecommend
			LEFT JOIN bodb02.dbo.custAccount mca WITH (NOLOCK) ON mca.custid = c.mrecommend
			LEFT JOIN bodb02.dbo.custAccount aca WITH (NOLOCK) ON aca.custid = c.recommend
			LEFT JOIN #CustGroup shl ON shl.groupid = sca.groupid 
			LEFT JOIN #CustGroup mhl ON mhl.groupid = mca.groupid 
			LEFT JOIN #CustGroup ahl ON ahl.groupid = aca.groupid 
			LEFT JOIN #CustGroup hl  ON hl.groupid = ca.groupid 
		WHERE  ul.logdate >= @__archiveDate AND ul.logdate < DATEADD(d,1,@ToDate) 
			AND ISNULL(ul.OldValue,0) <> ISNULL(ul.NewValue,0) AND (@Username = '' OR  ul.custid = @CustID)
			AND c.currency NOT IN (20,27,28)

		UNION ALL
		-- Result --> archive range
		SELECT  DATEPART(year,ul.logdate) Year, DATEPART(month,ul.logdate) Month, ul.logdate [LogDate],
				na.groupname Department, na.username Admin, c.username [Username], 
				CASE c.roleid WHEN 4 THEN 'Super'
							  WHEN 3 THEN 'Master'
							  WHEN 2 THEN 'Agent'
							  WHEN 1 THEN 'Member'
				ELSE '' END Level,
				ISNULL(shl.username,ISNULL(mhl.username,ISNULL(ahl.username,hl.username))) AS Headline
				, CASE WHEN c.roleid < 4 THEN s.username  
					 ELSE NULL END Super
				,CASE WHEN c.roleid < 3 THEN m.username
					 ELSE NULL END Master 
				, CASE WHEN c.roleid < 2 THEN  a.username 
					 ELSE NULL END Agent
				,case when ul.OldValue IS NULL then 0 else ul.OldValue end OldValue, 
				ul.NewValue, ul.doing Remark
		FROM bodb_CustomerLog_Archive.dbo.UserLog_Credit ul WITH (NOLOCK)
			INNER JOIN  #NAPadmin AS na  ON ul.userid = na.custid
			INNER JOIN bodb02.dbo.Customer c with (Nolock) ON ul.custid = c.custid
			LEFT JOIN bodb02.dbo.Customer a WITH(NOLOCK) ON c.recommend = a.custid
			LEFT JOIN bodb02.dbo.Customer m WITH(NOLOCK) ON c.mrecommend = m.custid
			LEFT JOIN bodb02.dbo.Customer s WITH(NOLOCK) ON c.srecommend = s.custid
			LEFT JOIN bodb02.dbo.custAccount ca WITH (NOLOCK) ON ca.custid = c.custid
			LEFT JOIN bodb02.dbo.custAccount sca WITH (NOLOCK) ON sca.custid = c.srecommend
			LEFT JOIN bodb02.dbo.custAccount mca WITH (NOLOCK) ON mca.custid = c.mrecommend
			LEFT JOIN bodb02.dbo.custAccount aca WITH (NOLOCK) ON aca.custid = c.recommend
			LEFT JOIN #CustGroup shl ON shl.groupid = sca.groupid 
			LEFT JOIN #CustGroup mhl ON mhl.groupid = mca.groupid 
			LEFT JOIN #CustGroup ahl ON ahl.groupid = aca.groupid 
			LEFT JOIN #CustGroup hl  ON hl.groupid = ca.groupid 
		WHERE  ul.logdate >= @FromDate AND ul.logdate < @__archiveDate 
			AND ISNULL(ul.OldValue,0) <> ISNULL(ul.NewValue,0) AND (@Username = '' OR  ul.custid = @CustID)
			AND c.currency NOT IN (20,27,28)
		ORDER BY ul.logdate ASC
	END
	

	DROP TABLE #CustGroup
	DROP TABLE #NAPadmin
	DROP TABLE #AdminGroup

END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_AdminUpdateCredit] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_AdminUpdateCredit] TO [vnteam]
GO