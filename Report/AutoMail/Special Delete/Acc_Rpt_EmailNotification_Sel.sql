/*<info serverAlias="DBOIC-bodb_OIC" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb_OIC]
GO

ALTER PROCEDURE dbo.Acc_Rpt_EmailNotification_Sel
	@LicenseeName     NVARCHAR(MAX) = 'ALL'
   , @CategoryId     INT = 7
   , @IsTest     BIT         = 0 
AS

/*
	Creator: Cherry
	Date: 2022-04-28
	DB: DBOIC.bodb_OIC
	Task: Get recipient list for Abnormal Bet
	Revisions:		
		- 20220428@Cherry: Get recipient list for Abnormal Bet (#171985)
		- 20220601@Cherry: Change the recipients (#173405)
		- 20231228@Cherry: Change mail starixvn to starixsoft (#198198)
		- 20240502@Cherry: Integrate SabaCoins (#203523)

	Param's Explanation:	 
*/

    BEGIN
	   SET NOCOUNT ON;

	   CREATE TABLE #tmpLicensee (LicenseeName NVARCHAR(50))
	   INSERT INTO #tmpLicensee (LicenseeName)
	   SELECT val
	   FROM dbo.strSplit (@LicenseeName, ',')

	   CREATE TABLE #BCC (LicGroup VARCHAR(50),	ContactEmail VARCHAR(50), IsTest BIT)

	   INSERT INTO #BCC (LicGroup, ContactEmail, IsTest) VALUES
		('Boping','lmd@bopingholdings.com',0),
		('Zelianta','lmd@zelianta.com',0),
		('Oneworks','lmd@enpine.com',0),
		('All','automail@enpine.com',0),
		('QC','qa@starixsoft.com',1),
		('Boping','kaka.huynh@starixsoft.com',1),
		('Zelianta','megan.dinh@starixsoft.com',1),
		('Oneworks','megan.dinh@nexcel.com',1)

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
			  FROM dbo.Licensee t1 WITH(NOLOCK) 
				LEFT JOIN dbo.LicenseeTypes lt WITH(NOLOCK) ON lt.TypeId = t1.TypeId
				INNER JOIN #BCC b ON (lt.TypeName = b.LicGroup 
										OR b.LicGroup = 'All'
										OR b.LicGroup = 'QC'
									) AND b.IsTest = @IsTest
			  WHERE t1.LicenseeId = t.LicenseeId
				FOR XML RAW('row'), ROOT('root')  
			) BccList
		FROM dbo.Licensee t WITH(NOLOCK)
			INNER JOIN dbo.LicenseeCategoryAssigned lc WITH(NOLOCK)    
					ON t.LicenseeId = lc.LicenseeId  
		WHERE lc.CategoryId = @CategoryId
			AND (@LicenseeName = 'ALL'
				OR RegisteredLicenseeName IN (SELECT LicenseeName FROM #tmpLicensee)
				)
		UNION
		SELECT 'SabaCoins' RegisteredLicenseeName,
			(SELECT 'automail@enpine.com' ContactEmail FOR XML RAW('row'), ROOT('root')) ToList,
			NULL CcList,
			NULL BccList

		DROP TABLE #tmpLicensee
		DROP TABLE #BCC

    END
