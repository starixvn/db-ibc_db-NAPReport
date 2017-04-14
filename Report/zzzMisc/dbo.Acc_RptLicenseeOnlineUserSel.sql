ALTER PROCEDURE [dbo].[Acc_RptLicenseeOnlineUserSel]
@fromdate	datetime,
@todate datetime,
@LicenseeName varchar(50)

AS
/*	Created by: Amy
	Date: 2011-03-23
	Task: Get peak concurrent users
	DB: DB03.ON_USER	
	
*/
BEGIN
	SET NOCOUNT ON	

Declare @ServerList table (Serverid int)
	
Insert into @ServerList
	
SELECT distinct l.Serverid FROM Site s WITH (nolock)
INNER JOIN On_User.dbo.ServerLists l WITH (nolock)
ON l.site=s.site
WHERE s.islicensee=1 AND isActive=1
	AND s.Site=@LicenseeName
	
SELECT TOP 1 SUM(Users) OnlineMemTotal
FROM TotalOnline WITH (NOLOCK)
WHERE ServerID IN (SELECT Serverid FROM @ServerList)
AND LogDate between @fromdate and @todate
GROUP BY logdate


END
GO
GRANT EXECUTE ON [dbo].[Acc_RptLicenseeOnlineUserSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_RptLicenseeOnlineUserSel] TO [VNTeam]