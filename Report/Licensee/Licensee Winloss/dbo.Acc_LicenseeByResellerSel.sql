USE [bodb_Licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[Acc_LicenseeByResellerSel]
	@ResellerID int=0,
	@ProductCode VARCHAR(10)='',
	@FromDate SMALLDATETIME,
	@ToDate  SMALLDATETIME,
	@ExcludeBA BIT = 0,
	@ExcludeTest BIT = 0
AS
/*
	Created by: [20110823@Henry]
	Task: Get List of all licensee 
	DB: DB052.bodb_licensee
	Revisions:
	- 20111117@Henry: only list licensees which have isDeposit = 1
	- 20111122@Henry: order by ResellerName and LicenseeName
	- 20120305@Henry: get dummy IBC Licensee
	- 20120306@Henry: get credit Licensees
	- 20120510@Henry: get licensees which have IsActive = 1
	- 20120704@Henry: Map Licensee with System
	- 20121119@Henry: Add param @ExcludeTest, if value = 1 then remove Spondemo
	- 20130222@Scott: add filter LicenseeProduct3rd.EffectiveDate <> null
	- 20130612@Jim: change codition for EffectiveDate
	- 20130621@Jim: fix bug wrong condition when inner join table LicenseeProduct3rd
	- 20130802@Jim: fix bug wrong LicenseeProduct3rd.EffectiveDate condition
	
*/

SET NOCOUNT ON

SET @ResellerID = ISNULL(@ResellerID,0)
SET @ProductCode = ISNULL(@ProductCode,'')
SET @ExcludeBA = ISNULL(@ExcludeBA,0)
SET @ExcludeTest = ISNULL(@ExcludeTest,0)
SELECT @Fromdate=ltrim(rtrim(@Fromdate)),@Todate=ltrim(rtrim(@Todate))  

CREATE TABLE #Data (ResellerID int,ResellerName varchar(50), ResellerType INT,LicenseeID INT, LicenseeName varchar(50))
DECLARE @ProductID INT

INSERT INTO #Data  (ResellerID,ResellerName, ResellerType,LicenseeID, LicenseeName)
SELECT	
	r.ResellerID
	,r.ResellerName
	,r.ResellerType
	,l.LicenseeID
	,l.LicenseeName	
FROM dbo.Licensees AS l WITH(NOLOCK)	
	INNER JOIN dbo.LicenseeReseller AS ls WITH(NOLOCK) ON l.LicenseeID=ls.LicenseeID 
		AND (@ResellerID=0 OR ls.ResellerID=@ResellerID)
	INNER JOIN dbo.Resellers AS r WITH(NOLOCK) ON r.ResellerID=ls.ResellerID
	INNER JOIN SystemLicensee sl (NOLOCK) ON l.LicenseeID=sl.LicenseeID 
	INNER JOIN Systems s (NOLOCK) ON sl.SystemID=s.ID 
	LEFT JOIN dbo.LicenseeProduct3rd ld WITH (NOLOCK)  ON l.LicenseeID=ld.LicenseeID
WHERE 
	(
		l.IsDeposit = 1 OR (l.IsDeposit=0 AND l.LicenseeID IN (SELECT DISTINCT LicenseeID FROM Labels WITH (NOLOCK)))
	)
	AND sl.IsActive = 1
	AND s.SystemName='Accounting'
	AND ((@ExcludeBA=0) OR (@ExcludeBA=1 AND r.ResellerID <> 3))
	AND (@ExcludeTest=0 OR (@ExcludeTest=1 AND r.ResellerID <> 6 ))
	AND (ISNULL(LTRIM(RTRIM(@ProductCode)),'')='' OR ((ISNULL(LTRIM(RTRIM(@ProductCode)),''))<>''))
ORDER BY l.IsDeposit DESC,r.ResellerName, l.LicenseeName

SET @ProductCode = ISNULL(LTRIM(RTRIM(@ProductCode)),'')
IF @ProductCode <> '' AND EXISTS(SELECT 1 FROM Product3rd WITH (NOLOCK) WHERE ProductPrefix = @ProductCode)
BEGIN
	IF @ProductCode<> 'BA'
	BEGIN
		DELETE FROM #Data WHERE ResellerID = 3
		SELECT @ProductID = ProductID FROM Product3rd WITH (NOLOCK) WHERE ProductPrefix = @ProductCode
		
		DELETE FROM #Data WHERE LicenseeID NOT IN (SELECT LicenseeID FROM LicenseeProduct3rd WITH (NOLOCK) WHERE ProductID=@ProductID and ISNULL(EffectiveDate,0)<>0) AND ResellerID NOT IN (4,8) --FDL, PIH
	END
	ELSE
	BEGIN
		DELETE FROM #Data WHERE ResellerID <> 3
	END

END

SELECT DISTINCT * FROM #Data ORDER BY ResellerID,ResellerType

DROP TABLE #Data
GO
GRANT EXECUTE ON [dbo].[Acc_LicenseeByResellerSel] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_LicenseeByResellerSel] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_LicenseeByResellerSel] TO [vnteam]