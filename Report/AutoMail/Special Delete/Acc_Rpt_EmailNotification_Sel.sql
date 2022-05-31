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
		- 20220601@Cherry: Change the recipients (#173405)

	Param's Explanation:	 
*/

    BEGIN
	   SET NOCOUNT ON;

	   CREATE TABLE #tmpLicensee (LicenseeName NVARCHAR(50))
	   INSERT INTO #tmpLicensee (LicenseeName)
	   SELECT val
	   FROM dbo.strSplit (@LicenseeName, ',')

	   CREATE TABLE #BCC (LicGroup VARCHAR(50),	ContactEmail VARCHAR(50))

	   INSERT INTO #BCC (LicGroup, ContactEmail) VALUES
		('Boping','lmd@bopingholdings.com'),
		('Zelianta','lmd@zelianta.com'),
		('Oneworks','lmd@enpine.com'),
		('All','automail@enpine.com')

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
			,(SELECT b.ContactEmail
			  FROM dbo.LicenseeTypes lt WITH(NOLOCK)
				INNER JOIN #BCC b ON (lt.TypeName = b.LicGroup OR b.LicGroup = 'All')
									AND lt.TypeId = t.TypeId
				FOR XML RAW('row'), ROOT('root')  
			) BccList
		FROM dbo.Licensee t WITH(NOLOCK)
			INNER JOIN dbo.LicenseeCategoryAssigned lc WITH(NOLOCK)    
					ON t.LicenseeId = lc.LicenseeId  
		WHERE lc.CategoryId = @CategoryId
			AND (@LicenseeName = 'ALL'
				OR RegisteredLicenseeName IN (SELECT LicenseeName FROM #tmpLicensee)
				)

		DROP TABLE #tmpLicensee
		DROP TABLE #BCC

    END
