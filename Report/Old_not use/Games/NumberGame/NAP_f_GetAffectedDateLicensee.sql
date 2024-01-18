/*<info serverAlias="DBACC-bodb02" selecters="bodbAdminNet" viewers="" isFunction="1" isNested="1"></info>*/
USE [bodb02]
GO

ALTER FUNCTION [dbo].[NAP_f_GetAffectedDateLicensee] (
	@iLevel TINYINT = 1 --1 @Product,2 @Sport,3 @Bettype	
	,@SiteID VARCHAR(8000) = ''
	,@IsDeposit BIT=1 -- NULL Get All, 1 : Deposit Site, 0 Credit Site
	,@FromDate SMALLDATETIME
	,@ToDate SMALLDATETIME
	,@GetIsActiveOnly BIT
	,@ExcludeLicenseeID INT
	,@SystemID INT	
	,@ProductPrefix VARCHAR(100),
	 @TrialData	BIT = 0
	)
RETURNS @tmpLscActive TABLE (
	LicenseeID INT
	,LicenseeName VARCHAR(100)
	,ProductID INT
	,SportType INT
	,BetType INT
	,EffectiveDate SMALLDATETIME
	,FromDate SMALLDATETIME
	,ToDate SMALLDATETIME
	)
AS
/*  Created: 20150316@Tom
    Task : Get Information
    DB: DBACC/bodb02
    
    Revisions:	
	   - 20171128@Tom: excluded condition @ExcludeLicenseeID (87164)
	   - 20180301@Kean: Missing number game data of some licensee (91266)
	   - 20181031@Percy: Remove linked-server DBLIC [RedmineID: #103660]
	   - 20210329@Roy: NAP Report - Support Saba789 (#151326)
		  
    Param's Explanation:
		SELECT * FROM [DW_f_GetAffectedDateLicensee] (1,'1,2,3', '2014-01-01','2015-05-01',1,18,3,'NG')
*/
BEGIN
	DECLARE @tblProductPrefix AS TABLE (ProductPrefix VARCHAR(10))
	
	--Get All Licensee
	SET @GetIsActiveOnly = 0

	INSERT INTO @tblProductPrefix (ProductPrefix)
	SELECT val
	FROM dbo.strSplit(@ProductPrefix, ',')

	DECLARE @tblSite TABLE (LicenseeID INT)

	INSERT INTO @tblSite (LicenseeID)
	SELECT val
	FROM dbo.strSplit(@SiteID, ',')
	
	DECLARE @tmpLicensees TABLE ( 
		LicenseeID INT
		,LicenseeName VARCHAR(50)
		,IsDeposit BIT
	)
	INSERT INTO @tmpLicensees ( 
		LicenseeID
		,LicenseeName
		,IsDeposit
	)
	SELECT LicenseeID
		,LicenseeName
		,IsDeposit
	FROM DBWH.bodb_Account.dbo.vw_Licensees WITH (NOLOCK)
	GROUP BY LicenseeID
		,LicenseeName
		,IsDeposit
	
	IF @iLevel = 1
	BEGIN
		INSERT INTO @tmpLscActive(
		LicenseeID
		,LicenseeName
		,ProductID
		,SportType
		,BetType
		,EffectiveDate
		,FromDate
		,ToDate)
		SELECT lp.LicenseeID
			,l.LicenseeName
			,lp.ProductID
			,NULL SportType
			,NULL BetType
			,lp.EffectiveDate
			,CASE
				WHEN @TrialData = 1 THEN @FromDate 
				WHEN @FromDate <= ISNULL(lp.EffectiveDate, '1900-01-01 00:00:00') THEN ISNULL(lp.EffectiveDate, '1900-01-01 00:00:00')
				ELSE @FromDate
				END FromDate
			,@ToDate ToDate
		FROM bodb_Licensee.dbo.LicenseeProduct3rd lp WITH (NOLOCK)
			INNER JOIN bodb_Licensee.dbo.Product3rd p3 WITH (NOLOCK) ON lp.ProductID = p3.ProductID
			INNER JOIN bodb_Licensee.dbo.SystemLicensee sl WITH (NOLOCK) ON lp.LicenseeID = sl.LicenseeID
			INNER JOIN @tmpLicensees l ON lp.LicenseeID = l.LicenseeID
			INNER JOIN bodb02.dbo.Products pr WITH (NOLOCK) ON p3.ProductPrefix = pr.ProductPrefix AND pr.Enabled =1
		WHERE sl.SystemID = @SystemID
			AND EXISTS (
				SELECT TOP 1 1
				FROM @tblProductPrefix tbl
				WHERE p3.ProductPrefix = tbl.ProductPrefix
				)
			AND (
				lp.EffectiveDate BETWEEN @FromDate
					AND @ToDate
				OR lp.EffectiveDate < @FromDate
				OR @TrialData = 1
				)
			AND (
				@GetIsActiveOnly = 0
				OR sl.IsActive = 1
				)
			AND (
				@IsDeposit IS NULL
				OR l.IsDeposit  = @IsDeposit
				)
			AND (@ExcludeLicenseeID <> lp.LicenseeID)
		GROUP BY lp.LicenseeID
			,l.LicenseeName
			,lp.ProductID
			,lp.EffectiveDate
			,CASE
				WHEN @TrialData = 1 THEN @FromDate 
				WHEN @FromDate <= ISNULL(lp.EffectiveDate, '1900-01-01 00:00:00') THEN ISNULL(lp.EffectiveDate, '1900-01-01 00:00:00')
				ELSE @FromDate
				END
	END
	ELSE IF @iLevel = 2
	BEGIN
		INSERT INTO @tmpLscActive(
		LicenseeID
		,LicenseeName
		,ProductID
		,SportType
		,BetType
		,EffectiveDate
		,FromDate
		,ToDate)
		SELECT lp.LicenseeID
			,l.LicenseeName
			,lp.ProductID
			,sbm.SportType
			,NULL BetType
			,lp.EffectiveDate
			,CASE
				WHEN @TrialData = 1 THEN @FromDate 
				WHEN @FromDate <= ISNULL(lp.EffectiveDate, '1900-01-01 00:00:00') THEN ISNULL(lp.EffectiveDate, '1900-01-01 00:00:00')
				ELSE @FromDate
				END FromDate
			,@ToDate ToDate
		FROM bodb_Licensee.dbo.LicenseeProduct3rd lp WITH (NOLOCK)
			INNER JOIN bodb_Licensee.dbo.Product3rd p3 WITH (NOLOCK) ON lp.ProductID = p3.ProductID
			INNER JOIN bodb_Licensee.dbo.SystemLicensee sl WITH (NOLOCK) ON lp.LicenseeID = sl.LicenseeID
			INNER JOIN @tmpLicensees l ON lp.LicenseeID = l.LicenseeID
			INNER JOIN bodb02.dbo.Products pr WITH (NOLOCK) ON p3.ProductPrefix = pr.ProductPrefix AND pr.Enabled =1
			INNER JOIN bodb02.dbo.SportBettypeMatrix sbm WITH (NOLOCK) ON sbm.ProductID = pr.ProductID AND sbm.Enabled =1
		WHERE sl.SystemID = @SystemID
			AND EXISTS (
				SELECT TOP 1 1
				FROM @tblProductPrefix tbl
				WHERE p3.ProductPrefix = tbl.ProductPrefix
				)
			AND (
				lp.EffectiveDate BETWEEN @FromDate
					AND @ToDate
				OR lp.EffectiveDate < @FromDate
				OR @TrialData = 1
				)
			AND (
				@GetIsActiveOnly = 0
				OR sl.IsActive = 1
				)
			AND (
				@IsDeposit IS NULL
				OR l.IsDeposit  = @IsDeposit
				)
			AND (@ExcludeLicenseeID <> lp.LicenseeID)
		GROUP BY lp.LicenseeID
			,l.LicenseeName
			,lp.ProductID
			,sbm.SportType
			,lp.EffectiveDate
			,CASE
				WHEN @TrialData = 1 THEN @FromDate 
				WHEN @FromDate <= ISNULL(lp.EffectiveDate, '1900-01-01 00:00:00') THEN ISNULL(lp.EffectiveDate, '1900-01-01 00:00:00')
				ELSE @FromDate
				END
	END
	ELSE IF @iLevel = 3
	BEGIN
		INSERT INTO @tmpLscActive(
		LicenseeID
		,LicenseeName
		,ProductID
		,SportType
		,BetType
		,EffectiveDate
		,FromDate
		,ToDate)
		SELECT lp.LicenseeID
			,l.LicenseeName
			,lp.ProductID
			,sbm.SportType
			,sbm.BetType
			,lp.EffectiveDate
			,CASE
				WHEN @TrialData = 1 THEN @FromDate 
				WHEN @FromDate <= ISNULL(lp.EffectiveDate, '1900-01-01 00:00:00') THEN ISNULL(lp.EffectiveDate, '1900-01-01 00:00:00')
				ELSE @FromDate
				END FromDate
			,@ToDate ToDate
		FROM bodb_Licensee.dbo.LicenseeProduct3rd lp WITH (NOLOCK)
			INNER JOIN bodb_Licensee.dbo.Product3rd p3 WITH (NOLOCK) ON lp.ProductID = p3.ProductID
			INNER JOIN bodb_Licensee.dbo.SystemLicensee sl WITH (NOLOCK) ON lp.LicenseeID = sl.LicenseeID
			INNER JOIN @tmpLicensees l ON lp.LicenseeID = l.LicenseeID
			INNER JOIN bodb02.dbo.Products pr WITH (NOLOCK) ON p3.ProductPrefix = pr.ProductPrefix AND pr.Enabled =1
			INNER JOIN bodb02.dbo.SportBettypeMatrix sbm WITH (NOLOCK) ON sbm.ProductID = pr.ProductID AND sbm.Enabled =1
		WHERE sl.SystemID = @SystemID
			AND EXISTS (
				SELECT TOP 1 1
				FROM @tblProductPrefix tbl
				WHERE p3.ProductPrefix = tbl.ProductPrefix
				)
			AND (
				lp.EffectiveDate BETWEEN @FromDate
					AND @ToDate
				OR lp.EffectiveDate < @FromDate
				OR @TrialData = 1
				)
			AND (
				@GetIsActiveOnly = 0
				OR sl.IsActive = 1
				)
			AND (
				@IsDeposit IS NULL
				OR l.IsDeposit  = @IsDeposit
				)
			AND (@ExcludeLicenseeID <> lp.LicenseeID)
		GROUP BY lp.LicenseeID
			,l.LicenseeName
			,lp.ProductID
			,sbm.SportType
			,sbm.BetType
			,lp.EffectiveDate
			,CASE
				WHEN @TrialData = 1 THEN @FromDate 
				WHEN @FromDate <= ISNULL(lp.EffectiveDate, '1900-01-01 00:00:00') THEN ISNULL(lp.EffectiveDate, '1900-01-01 00:00:00')
				ELSE @FromDate
				END
	END
	
	IF (EXISTS(SELECT TOP 1 1 FROM @tblSite s WHERE s.LicenseeID <> 0))
	BEGIN
		DELETE tmp
		FROM @tmpLscActive tmp
			LEFT JOIN @tblSite s ON tmp.LicenseeID = s.LicenseeID
		WHERE s.LicenseeID Is Null
	END
	
	RETURN
END
GO