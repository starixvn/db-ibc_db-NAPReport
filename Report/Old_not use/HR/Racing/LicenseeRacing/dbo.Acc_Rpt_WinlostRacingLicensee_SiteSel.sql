 CREATE PROCEDURE [dbo].[Acc_Rpt_WinlostRacingLicensee_SiteSel]
	AS
/*
	Created by: Johnson
	Date: 2011-04-14
	Task: Racing Licensee Report  
	DB: DB06.BODB02

	Revisions:
		
	Param's Explanation:
		
*/
	SET NOCOUNT ON
	
	SELECT siteid, site
	FROM site WITH(NOLOCK)
	WHERE isLicensee = 1 AND isActive =1 
		AND siteid NOT IN (29,35,38,39)

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostRacingLicensee_SiteSel] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostRacingLicensee_SiteSel] TO [Dot_Member]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostRacingLicensee_SiteSel] TO [vnteam]