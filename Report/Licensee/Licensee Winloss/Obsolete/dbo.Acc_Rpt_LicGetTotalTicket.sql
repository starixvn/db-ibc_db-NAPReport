USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[Acc_Rpt_LicGetTotalTicket]    
	@NormalLicensee VARCHAR(1000),
	@BALicensee VARCHAR(1000),
	@FromDate		SMALLDATETIME,  
	@ToDate			SMALLDATETIME,  
	@showSB			BIT=1,
	@ShowRB			BIT=0,
	@ShowNG			BIT=0,
	@ShowLC			BIT=0,
	@ShowVS			BIT=0,
	@ShowCS			BIT=0,
	@ShowKN  	    BIT=0,
	@showGD 		BIT=0,-- Gold Deluxe
	@showVG 		BIT=0, --Vegas Games
	@showAGCS 		BIT=0, --AG Casino
	@SportID		INT=0,
	@bettype		INT=0,
	@ReportBy		TINYINT=0,  
	@GroupBy		TINYINT=1,  
	@Debug			BIT = 0
AS    
/*  Created: Henry    
 Date: 2012-10-26    
    Task : Get Total tickets of Licensees    
    DB: DB052.bodb02    
    Original: OA_Rpt_GetTotalTicket 
    Revisions:    
		-20130607@Jim: support RNG Casino 
		-20140401@Hannah: offer Keno
		-20140421@Hannah: fix bug for Keno
		-20140704@Jim: offer Sporting solution
		-20150710@Jim:  Super Balance fix (Feature #38168)
		- 20150723@Jim: Apply Bettrade [#38815]	
	Param's Explanation:    
	+ @ReportBy 1-Live; 2-Non-Live; 0: All;  
	+ @GroupBy 1-Daily; 2-Monthly
	+ @showSB: Show SportsBook bets
	+ @ShowRB: Show RB bets
	+ @ShowNG: Show Number game bets
	+ @ShowLC: Show Live casino
	+ @ShowVS: Show Virtual Sports
	+ @ShowCS: Show RNG Casino   
*/    
BEGIN    

declare @sql varchar(MAX)

SELECT @sql = 'SET NOCOUNT ON  ' + char(13)

--declare
SELECT @sql = @sql + '--Declare variable:' + char(13)

SELECT @sql = @sql +	
				'DECLARE @data AS TABLE (WinlostDate SMALLDATETIME ,ResellerID INT,LicenseeID INT, betcount INT) ' + char(13) +
				'DECLARE @tmpLicenseeReseller AS TABLE (ResellerID INT ,LicenseeID INT,AffectedDate SMALLDATETIME)' + char(13) +
				'DECLARE @i INT' + char(13) +
				'DECLARE @tempBettype AS TABLE (bettype INT PRIMARY KEY)' + char(13) 				
		
--Get Licensee List
--1 Normal
IF LTRIM(RTRIM(ISNULL(@NormalLicensee,''))) <> ''
BEGIN
	SELECT @sql = @sql + '--Get normal licensee list:' + char(13)
	SELECT @sql = @sql + 
					'INSERT INTO @tmpLicenseeReseller (ResellerID,LicenseeID,AffectedDate)' + char(13) +
					'SELECT lr.ResellerID,lr.LicenseeID,
					CASE WHEN '''+CONVERT(VARCHAR(10),@fromdate,120)+'''<=l.AffectedDate THEN l.AffectedDate ELSE '''+CONVERT(VARCHAR(10),@fromdate,120)+'''END '+ char(13) +
					'FROM bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)' + char(13) +
					'INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK ) ON lr.LicenseeID=l.LicenseeID'+char(13)+
					'INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID' + char(13) +
					'WHERE  r.ResellerID <> 3 AND' + char(13) +
					'		lr.LicenseeID IN (' + @NormalLicensee + ')'  + char(13) 
END
					
--2 BA Licensee
IF LTRIM(RTRIM(ISNULL(@BALicensee,''))) <> ''
BEGIN
	SELECT @sql = @sql + '--Get BA licensee list:' + char(13)
	SELECT @sql = @sql + 
					'INSERT INTO @tmpLicenseeReseller (ResellerID,LicenseeID,AffectedDate)' + char(13) +
					'SELECT lr.ResellerID,lr.LicenseeID,
					CASE WHEN '''+CONVERT(VARCHAR(10),@fromdate,120)+'''<=l.AffectedDate THEN l.AffectedDate ELSE '''+CONVERT(VARCHAR(10),@fromdate,120)+'''END '+ char(13) +
					'FROM bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)' + char(13) +
					'INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID' + char(13) +
					'INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK ) ON lr.LicenseeID=l.LicenseeID'+char(13)+
					'WHERE  r.ResellerID = 3 AND' + char(13) +
					'		lr.LicenseeID IN (' + @BALicensee + ')'  + char(13) 
END				

--Get the data
SELECT @sql = @sql + '--Get the data:' + char(13)
IF (@ShowSB = 1 OR @ShowRB = 1 OR @ShowNG = 1 OR @ShowLC = 1 OR @ShowVS = 1 OR @ShowCS=1 OR @ShowKN=1 OR @showGD = 1 OR @showVG = 1 OR  @showAGCS  = 1)
BEGIN
	--exclude BA & IBC & PIH...
	SELECT @sql = @sql + '--Exclude BA & IBC & PIH...:' + char(13)
	SELECT @sql = @sql + 
				'IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr INNER JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid  WHERE l.IsDeposit=1 AND lr.ResellerID<>3)' + char(13) +
				'BEGIN' + char(13) +
					'INSERT INTO @data' + char(13) +
					'SELECT  b.rptDate,lr.ResellerID,lr.licenseeid, SUM(BetCount) AS betcount' + char(13) +
					'FROM @tmpLicenseeReseller lr' + char(13) +
						'INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid'+ char(13) +
						'INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID' + char(13) +
						'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + char(13) +
					'WHERE ' + char(13) +
						'b.rptDate BETWEEN lr.AffectedDate AND  ''' + convert(varchar(10),@ToDate, 120) + '''' + char(13) +
						'AND lr.ResellerID<>3' + char(13) + --BA
						'AND lic.isdeposit=1'+ char(13) +
						--'AND b.rptDate >= isnull(lic.AffectedDate,''1999-01-01'')' + char(13) +
						'AND b.status NOT IN (-1,103) ' + char(13) +
						'AND CurrencyID<>20 ' + char(13) +
						'AND (b.bettype < ' + CASE WHEN @ShowSB=1 THEN + ' 31 OR (b.bettype BETWEEN 121 AND 999 AND b.bettype NOT IN (901,902,903)) OR b.bettype BETWEEN 1301 AND 1399' ELSE '0' END +
						CASE WHEN @ShowRB = 1 THEN ' OR b.bettype BETWEEN 31 AND 33' ELSE '' END + 
						CASE WHEN @ShowLC = 1 THEN ' OR b.bettype BETWEEN 1101 AND 1199' ELSE '' END + 
						CASE WHEN @ShowVS = 1 THEN ' OR b.bettype BETWEEN 1201 AND 1299' ELSE '' END + 
						CASE WHEN @ShowCS = 1 THEN ' OR b.bettype =71' ELSE '' END + 
						CASE WHEN @ShowKN = 1 THEN ' OR b.bettype BETWEEN 1501 AND 1599' ELSE '' END + 
						CASE WHEN @ShowNG = 1 THEN ' OR b.bettype BETWEEN 81 AND 120' ELSE '' END   + char(13) +
						CASE WHEN @showGD = 1 THEN ' OR b.bettype = 1700' ELSE '' END   + char(13) +
						CASE WHEN @showVG = 1 THEN ' OR b.bettype = 1900' ELSE '' END   + char(13) +
						CASE WHEN @showAGCS  = 1 THEN ' OR b.bettype = 1800' ELSE '' END + ')' + char(13) +
						CASE WHEN @bettype <> 0 THEN ' AND b.bettype = ' + convert(varchar(10), @Bettype)  ELSE '' END + char(13) +
						CASE WHEN @SportID<>0 THEN 'AND b.bettype NOT IN (9,29) AND b.bettype NOT BETWEEN 31 AND 120 AND l.Sporttype = ' + convert(varchar(10), @SportID) ELSE '' END + char(13) +
						CASE 
							WHEN @ReportBy=1 THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10,31,32,33) '
							WHEN @ReportBy=2 THEN 'AND b.IsLive=0 '
							ELSE '' END + char(13) +
						'GROUP BY b.rptDate,lr.ResellerID,lr.licenseeid ' + char(13) +							
				'END' + char(13) 
	--BA
	SELECT @sql = @sql + '--BA selection' + char(13)
	IF @ShowSB = 1
	BEGIN
		SELECT @sql = @sql + 
				'IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller WHERE ResellerID = 3)' + char(13) +
				'BEGIN' + char(13) +
					'INSERT INTO @data' + char(13) +
					'SELECT b.rptDate, lr.ResellerID,lr.licenseeid, SUM(BetCount) AS betcount ' + char(13) +
					'FROM @tmpLicenseeReseller lr' + char(13) +
						'INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid'+ char(13) +
						'INNER JOIN bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID' + char(13) +
						'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + char(13) +
					'WHERE ' + char(13) +
						'b.rptDate BETWEEN lr.AffectedDate AND  ''' + convert(varchar(10),@ToDate, 120) + '''' + char(13) +
						'AND lr.ResellerID=3'+ char(13) +
						'AND lic.isdeposit=1'+ char(13) +
						--'AND b.rptDate >= isnull(lic.AffectedDate,''1999-01-01'')' + char(13) +
						'AND b.status NOT IN (-1,103) ' + char(13) +
						'AND CurrencyID<>20 ' + char(13) +
						'AND b.bettype NOT IN (901,902,903)'+CHAR(13)+
						CASE WHEN @bettype<>0 THEN 'AND b.bettype = ' + convert(varchar(10), @Bettype)  ELSE '' END + char(13) +	
						CASE WHEN @SportID<>0 THEN 'AND b.bettype NOT IN (9,29)  AND l.Sporttype = ' + convert(varchar(10), @SportID)  ELSE '' END + char(13) +
						CASE 
							WHEN @ReportBy=1 THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10) '
							WHEN @ReportBy=2 THEN 'AND b.IsLive=0 '
							ELSE '' END + char(13) +
						'GROUP BY b.rptDate,lr.ResellerID,lr.licenseeid' + char(13) +
				'END' + char(13)
	END
	--FDL + PIH...
	SELECT @sql = @sql + '--FDL + PIH selection ...' + char(13)
	SELECT @sql = @sql + 
				'IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr inner JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid where l.IsDeposit=0)' + char(13) +
				'BEGIN' + char(13) +
					'INSERT INTO @data' + char(13) +
					'SELECT b.rptDate,lr.ResellerID,lr.LicenseeID ,SUM(BetCount) AS betcount' + char(13) +
					'FROM @tmpLicenseeReseller lr ' + char(13) +
					'INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID' + char(13) +
					'INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID=lb.LabelID' + char(13) +
						'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + char(13) +
					'WHERE ' + char(13) +
						'b.rptDate BETWEEN lr.AffectedDate AND ''' + convert(varchar(10),@ToDate, 120) + '''' + char(13) +
						'AND b.status NOT IN (-1,103) ' + char(13) +
						'AND lr.ResellerID<>3' + char(13) + --BA
						--'AND b.rptDate >= isnull(lb.AffectedDate,''1999-01-01'')' + char(13) +
						'AND CurrencyID<>20 ' + char(13) +
						'AND isnull(b.customercategory,-1) NOT IN (27,28) ' + char(13) +
						'AND (b.bettype < ' + CASE WHEN @ShowSB=1 THEN + ' 31 OR (b.bettype BETWEEN 121 AND 999 AND b.bettype NOT IN (901,902,903)) OR b.bettype BETWEEN 1301 AND 1399' ELSE '0' END +
						CASE WHEN @ShowRB = 1 THEN ' OR b.bettype BETWEEN 31 AND 33' ELSE '' END + 
						CASE WHEN @ShowLC = 1 THEN ' OR b.bettype BETWEEN 1101 AND 1199' ELSE '' END +
						CASE WHEN @ShowVS = 1 THEN ' OR b.bettype BETWEEN 1201 AND 1299' ELSE '' END +
						CASE WHEN @ShowCS = 1 THEN ' OR b.bettype =71' ELSE '' END +
						CASE WHEN @ShowKN = 1 THEN ' OR b.bettype BETWEEN 1501 AND 1599' ELSE '' END +
						CASE WHEN @ShowNG = 1 THEN ' OR b.bettype BETWEEN 81 AND 120' ELSE '' END   + char(13) +
						CASE WHEN @showGD = 1 THEN ' OR b.bettype = 1700' ELSE '' END   + char(13) +
						CASE WHEN @showVG = 1 THEN ' OR b.bettype = 1900' ELSE '' END   + char(13) +
						CASE WHEN @showAGCS  = 1 THEN ' OR b.bettype = 1800' ELSE '' END + ')' + char(13) +
						CASE WHEN @bettype <> 0 THEN ' AND b.bettype = ' + convert(varchar(10), @Bettype)  ELSE '' END + char(13) +
						CASE WHEN @SportID<>0 THEN 'AND b.bettype NOT IN (9,29) AND b.bettype NOT BETWEEN 31 AND 120 AND l.Sporttype = ' + convert(varchar(10), @SportID)  ELSE '' END + char(13) +
						CASE 
							WHEN @ReportBy=1 THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10,31,32,33) '
							WHEN @ReportBy=2 THEN 'AND b.IsLive=0 '
							ELSE '' END + char(13) +
						'GROUP BY b.rptDate,lr.ResellerID,lr.LicenseeID ' + char(13) +	
				'END' + char(13)		
END			
			
SELECT @sql = @sql + 
			'SELECT ' + char(13) +
				CASE 
					WHEN @GroupBy = 1 THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) ' 
					WHEN @GroupBy = 2 THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
					END + ' GroupBy,' + char(13) +
				'r.ResellerID,r.ResellerName,l.LicenseeName,ISNULL(SUM(d.betcount),0) AS BetCount' + char(13) +	
			'FROM @data d ' + char(13) +	
				'INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = d.ResellerID' + char(13) +
				'INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON l.LicenseeID = d.LicenseeID' + char(13) +
			'GROUP BY ' + char(13) +
				CASE 
					WHEN @GroupBy = 1 THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) ' 
					WHEN @GroupBy = 2 THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
					END + char(13) +
			',r.ResellerID,r.ResellerName, l.LicenseeName ' + char(13) +	
			'ORDER BY ' + char(13) +
			CASE 
					WHEN @GroupBy = 1 THEN 'CONVERT(VARCHAR(8),d.winlostdate,112) ' 
					WHEN @GroupBy = 2 THEN 'CONVERT(VARCHAR(6),d.winlostdate,112)'
					END + char(13) +
			',r.ResellerName, l.LicenseeName ' + char(13) 				

IF (@debug = 1) PRINT @sql
ELSE EXEC(@sql)

END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_LicGetTotalTicket] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LicGetTotalTicket] TO [vnteam]  
