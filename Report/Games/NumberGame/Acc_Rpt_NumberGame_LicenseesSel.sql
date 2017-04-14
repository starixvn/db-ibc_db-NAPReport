USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_NumberGame_LicenseesSel]    Script Date: 11/06/2012 03:44:34 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_NumberGame_LicenseesSel    Script Date: 9/13/2012 1:49:08 PM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_NumberGame_LicenseesSel]
AS
	/*
		Created: Johnson
		Date: 25Oct2011
		Task: Get list licensees offered number game
		DB: DB052.bodb02
		
		Revisions:
		- 20120913@Henry: Using ProductPrefix instead of ProductName
		- 20121006@Daniel: Only get deposit licensees
		- 20130624@Jim: support to show licensee Active only
		
		
		Parameters Explanation:
	*/
SET NOCOUNT ON 

	SELECT l.LicenseeID, l.Licenseename
	FROM bodb_Licensee.dbo.Product3rd p WITH (nolock)
		INNER JOIN bodb_Licensee.dbo.LicenseeProduct3rd lp WITH (nolock) ON lp.productid = p.productid
		INNER JOIN bodb_Licensee.dbo.Licensees l WITH (nolock) ON l.licenseeid = lp.licenseeid
		INNER JOIN bodb_licensee.dbo.SystemLicensee sl WITH (NOLOCK) ON sl.LicenseeID=l.LicenseeID AND sl.SystemID=3
	WHERE  ProductPrefix = 'NG' 
		   AND IsDeposit = 1
		   AND sl.isActive=1		
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_NumberGame_LicenseesSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NumberGame_LicenseesSel] TO [vnteam]