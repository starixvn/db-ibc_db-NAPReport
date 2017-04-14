USE [bodb_Licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER   PROCEDURE  [dbo].[Acc_KenoCurrencySelByLicensee]		
	@LicenseeID  VARCHAR(500)
AS	
/*
Created: 20140613@Jim
Task : Get all the currency by a licensee
DB: DBLIC.bodb_licensee


Revisions:
    
Param's Explanation:
	@LicenseeID :(string) list of selected licensee,separate by comma (,)
*/

/*
Acc_KenoCurrencySelByLicensee		
	--@LicenseeID  ='13,18,1'
	@LicenseeID  ='1'
	
*/
IF ISNULL(@LicenseeID,'')=''
RETURN

--- declare variable 
DECLARE @tblsite AS TABLE (siteid INT)
DECLARE @tbllicensee AS TABLE (licenseeid INT )
--- init variable 
INSERT INTO  @tblsite (siteid)
SELECT VAL siteid 
FROM strSplit(@LicenseeID,',')
		
INSERT INTO  @tbllicensee (licenseeid)
SELECT s.siteid as licenseeId
FROM @tblsite s 
INNER JOIN dbo.Licensees l WITH (NOLOCK) ON l.LicenseeID=s.siteid 
WHERE s.siteid NOT IN (13,18)

IF EXISTS (SELECT 1 FROM @tblsite WHERE siteid  IN (13,18))
	BEGIN 
		INSERT INTO @tbllicensee (licenseeid)
		SELECT LabelID AS licenseeID
		FROM dbo.Labels lb WITH (NOLOCK)
		INNER JOIN @tblsite  s ON lb.LicenseeID=s.siteid
		WHERE lb.LicenseeID in (13,18)
   END

SELECT DISTINCT 
		CASE 
			WHEN b.CurrencyID = 51 THEN 'INH'
			ELSE e.Code 
		END AS CurrencyCode
FROM dbo.rpt_Betting b WITH (NOLOCK) 
	INNER JOIN 	@tbllicensee l ON l.licenseeid=b.SiteID
	INNER JOIN bodb02.dbo.exchange e with (nolock) ON b.CurrencyID = e.exchangeid
WHERE b.Bettype BETWEEN 1501 AND 1599 
	AND b.CurrencyID NOT IN (20,27,28)
	ORDER BY 
		CASE 
			WHEN b.CurrencyID = 51 THEN 'INH'
			ELSE e.Code 
		END
		
GO
GRANT EXECUTE ON [dbo].[Acc_KenoCurrencySelByLicensee] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_KenoCurrencySelByLicensee] TO [vnteam]
		