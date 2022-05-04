/*<info serverAlias="DBOIC-bodb_OIC" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb_OIC]
GO

ALTER PROCEDURE dbo.Acc_Rpt_EmailNotification_Sel
	@LicenseeName     NVARCHAR(MAX) = 'ALL'
   , @CategoryId     INT = 7
AS

/*
	Creator: Cherry
	Date: 2022-04-28
	DB: DBOIC.bodb_OIC
	Task: Get recipient list for Abnormal Bet
	Revisions:		
		- 20220428@Cherry: Get recipient list for Abnormal Bet (#171985)

	Param's Explanation:	 
*/

    BEGIN
	   SET NOCOUNT ON;

	   CREATE TABLE #tmpLicensee (LicenseeName NVARCHAR(50))
	   INSERT INTO #tmpLicensee (LicenseeName)
	   SELECT val
	   FROM dbo.strSplit (@LicenseeName, ',')

	   SELECT t.RegisteredLicenseeName 
			,(SELECT c.ContactEmail  
				FROM dbo.CategoryContact cc WITH(NOLOCK)  
					INNER JOIN dbo.Contact c WITH(NOLOCK)   
						ON c.ContactID = cc.ContactID   
							AND cc.RecipientType = 0   
							AND cc.CategoryID = lc.CategoryId   
							AND c.LicenseeID = t.LicenseeId  
				FOR XML RAW('row'), ROOT('root')  
			) ToList  
		   ,(SELECT c.ContactEmail  
				FROM dbo.CategoryContact cc WITH(NOLOCK)  
					INNER JOIN dbo.Contact c WITH(NOLOCK)   
						ON c.ContactID = cc.ContactID   
						   AND cc.RecipientType = 1   
						   AND cc.CategoryID = lc.CategoryId   
						   AND c.LicenseeID = t.LicenseeId  
				FOR XML RAW('row'), ROOT('root')  
			) CcList  
		FROM dbo.Licensee t WITH(NOLOCK)
			INNER JOIN dbo.LicenseeCategoryAssigned lc WITH(NOLOCK)    
					ON t.LicenseeId = lc.LicenseeId  
		WHERE lc.CategoryId = @CategoryId
			AND (@LicenseeName = 'ALL'
				OR RegisteredLicenseeName IN (SELECT LicenseeName FROM #tmpLicensee)
				)

		DROP TABLE #tmpLicensee

    END
