USE [ON_USER]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_LicenseeOnlineUserSel]    Script Date: 04/11/2011 08:44:56 ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_LicenseeOnlineUserSel]
	@fromdate datetime,
	@todate datetime,
	@LicenseeName varchar(50)

AS
/*	Created by: Amy
	Date: 2011-03-23
	Task: Get peak concurrent users for Licensee
	DB: DB03.ON_USER	

	Revisions:
		- 20110412@Sylvia: Change how to get SERVERID 
		- 20121205@Johnson: fix bug if Licensee have more servers
	
*/
BEGIN
SET NOCOUNT ON	

DECLARE @tmpServer TABLE(ServerID int)

INSERT INTO @tmpServer (serverid)	
SELECT Serverid FROM bodb02.dbo.Site s WITH (nolock)
WHERE s.Site=@LicenseeName

SELECT max(TotalUser) as totalUser,dateadd(d, datediff(day, 0, logdate), 0) as logdate
FROM(
	SELECT sum(Users) as TotalUser, logdate
	FROM TotalOnline WITH (NOLOCK)
	WHERE LEFT(ServerID,3) IN (SELECT LEFT(ServerID,3) FROM @tmpServer)
	AND LogDate between @fromdate and @todate
	GROUP BY LogDate
	UNION ALL

	SELECT sum(Users) as TotalUser, LogDate
	FROM TotalOnline_BK WITH (NOLOCK)
	WHERE LEFT(ServerID,3) IN (SELECT LEFT(ServerID,3) FROM @tmpServer)
	AND LogDate between @fromdate and @todate
	GROUP BY LogDate
)r 
GROUP BY dateadd(d, datediff(day, 0, logdate), 0)
ORDER BY logdate

END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_LicenseeOnlineUserSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LicenseeOnlineUserSel] TO [vnteam]