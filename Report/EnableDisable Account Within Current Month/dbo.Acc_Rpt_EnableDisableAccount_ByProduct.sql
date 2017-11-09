USE [bodb02]
GO
 
ALTER PROCEDURE [dbo].[Acc_Rpt_EnableDisableAccount_ByProduct]
	@ListCurrency	VARCHAR(8000)	= 'all', 
	@SportType		INT,
	@ShowEnabled	BIT				=	1,
	@ShowDisabled	BIT				=	1
AS  
/*  Created: Dominic 
	Date: 2014-06-02  
    Task : Total Credit Accounts Enabled/Disabled per Product
    DB: DBACC/bodb02
   
    Revisions:  
		- 20140627@Dominic: Exclude special super with username  LIKE '3rdSuper%','STEST%','%ACCSuper%'
		- 20140707@Dominic: Add Param @ShowEnabled/@ShowDisabled #18655
		- 20150609@Kos: Separate CustDB to DBCUST server (Move SP to DBACC.bodb02)
		- 20150828@Jim: support GoldDeluxe & Metric Gaming(#40262)
		- 20150828@Jim: support Colossus Bet (#42608)
		- 20151215@Percy: support Cockfighting [Redmine: #49027]
		- 20160108@Percy: Add new range bettype for Casino [Redmine: #49134]
		- 20160229@Jim: Offer Allbet [Redmine #50921]
		- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model [RedmineID: #55589]		
		- 20160916@Robert:
			1. Integrate new product NG2 [RedmindID: #63460]
			2. Clean code of Cockfighting
		- 20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]  
		- 20170627@Cherry: Integrate Lottery and Betradar Virtual Sports (#78184, 78495)
		- 20170825@Cherry: Integrate Lucky 3 (#78214)
		- 20171109@Kean: HotFix #86404 - List of Currencies is passed incorrectly

	Param's Explanation:  
	  + @ListCurrency: The specified date used as one of the filter criterias, if its value is 'all' then no need to be filtered by currency
	  + {251:Casino (include: 251, 208, 209, 210), 151:Racing,252:Bingo,161:Number Game,162:Live Casino,180:Virtual Sports,202:Keno}
			220: Lottery
*/  
BEGIN
	SET NOCOUNT ON
	
	--Table of real creadit super filter by currency
	CREATE TABLE #FiltedCreditSuper(
			CustID INT,
			SuperStatus BIT
			)
	DECLARE @DepositDummySuper TABLE  (
		CustID INT
		)
			
	--Table of Super/master/Member that belong to real super above	
	CREATE TABLE #FiltedDownlineAcc(
		SuperID		INT,
		CustID		INT,
		RoleID		INT,
		IsDisable	BIT
		)	
	
	--Get real credit super filterd by currencies	
	INSERT INTO @DepositDummySuper
	SELECT custid FROM dbo.Dep_CustSuper
	UNION
	SELECT custid FROM dbo.Acc_CustDirect WHERE roleid = 4

	-- DCS setting --
	DECLARE @bitmapOrder TABLE (bitmapOrder TINYINT) -- using for sporttype that has many settings
	IF @SportType = 211
	BEGIN
		INSERT INTO @bitmapOrder (bitmapOrder)
		SELECT bitmapOrder FROM dbo.ProductStatusProfile WITH(NOLOCK) WHERE Sporttype = @SportType
	END

	DECLARE @bitmap TINYINT -- using for sporttype that has 1 setting
	IF @SportType IN (212, 213, 219, 220, 180, 160) -- Macau Games, NG2, Fishing World, Virtual Sports, Lottery, Lucky 3
	BEGIN
		SELECT  @bitmap = bitmapOrder 
		FROM dbo.ProductStatusProfile WITH(NOLOCK) 
		WHERE Sporttype = @SportType 
	END
	-- end DCS setting --
	
	INSERT INTO #FiltedCreditSuper(CustID,SuperStatus)
	SELECT ci.custid,
		CASE
			WHEN @sportType = 151 THEN (ci.Disable151_AU & ci.Disable152_AU & ci.Disable152_UK & ci.Disable153_AU & ci.DisableHorseRacing & ci.DisableOpenTote)
			WHEN @sportType = 161 THEN ci.DisableNumber
			WHEN @sportType = 202 THEN CASE WHEN EXISTS(SELECT TOP 1 1 FROM dbo.CustGameType gt WITH(NOLOCK,INDEX=PK_CustGameType)
																WHERE gt.CustID = ci.CustID AND gt.IsDisabled = 0 ) 
																THEN 0 
																ELSE 1 
																END
			WHEN @sportType = 162 THEN (~ci.SyncLiveCasino | ci.DisableLiveCasino)
			WHEN @sportType = 251 THEN (~ci.SyncCasino |(ci.DisableCasino))
			WHEN @sportType = 252 THEN (~ci.SyncBingo | ci.DisableBingo)
			WHEN @sportType = 255 THEN ci.DisableGoldDeluxe
			WHEN @sportType = -1  THEN ci.DisableSuperLive
			WHEN @sportType = 204 THEN ci.DisableColossusBet
			WHEN @SportType = 211 THEN (SELECT CASE MIN(CONVERT(INT, f.value)) WHEN 0 THEN 0 ELSE 1 END
												FROM CustProductStatus cps WITH(NOLOCK)
												CROSS APPLY @bitmapOrder b
												CROSS APPLY f_CustSetting_ProductStatusSel(cps.bitmapIsDisabled, b.bitmapOrder) f
											WHERE custid = ci.custid)
			WHEN @SportType IN (212, 213, 219, 220, 180, 160) THEN (SELECT CASE (SELECT value FROM dbo.f_CustSetting_ProductStatusSel(bitmapIsDisabled, @bitmap)) WHEN 0 THEN 0 ELSE 1 END 
										FROM CustProductStatus
										WHERE custid = ci.custid)
		END
	FROM dbo.custInfo ci WITH(NOLOCK)
	JOIN dbo.CustSuper cs WITH(NOLOCK) ON ci.custid = cs.custid AND cs.IsInternal = 0	
	WHERE ci.roleid=4 AND ci.Enabled = 1 AND ci.custid NOT IN ( SELECT custid
																FROM dep_custsuper WITH(NOLOCK))
		AND (@ListCurrency= 'all' OR ci.currency IN(SELECT val
                            FROM   dbo.strSplit (@ListCurrency, ','))) AND ci.currency NOT IN (20,27,28)
        AND ci.custid NOT IN (SELECT * FROM @DepositDummySuper)
        AND ci.username NOT LIKE '3rdSuper%'
        AND ci.username NOT LIKE 'STEST%'
        AND ci.username NOT LIKE '%ACCSuper%'
	    
	IF @ShowEnabled = 1 AND @ShowDisabled = 0
	BEGIN
		DELETE FROM #FiltedCreditSuper
		WHERE  SuperStatus = 1
	END
	
	IF @ShowEnabled = 0 AND @ShowDisabled = 1
	BEGIN
		DELETE FROM #FiltedCreditSuper
		WHERE  SuperStatus = 0
	END
	
	IF @ShowEnabled = 0 AND @ShowDisabled = 0
	BEGIN
		DELETE FROM #FiltedCreditSuper
	END
	    
	--Get data for downline list 
    IF @sportType = 151
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			(ci.Disable151_AU & ci.Disable152_AU & ci.Disable152_UK & ci.Disable153_AU & ci.DisableHorseRacing & ci.DisableOpenTote)
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustMaster cm WITH(NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 3
		WHERE ci.Enabled = 1 
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			(ci.Disable151_AU & ci.Disable152_AU & ci.Disable152_UK & ci.Disable153_AU & ci.DisableHorseRacing & ci.DisableOpenTote)
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustAgent ca WITH(NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 2 
		WHERE ci.Enabled = 1
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			(ci.Disable151_AU & ci.Disable152_AU & ci.Disable152_UK & ci.Disable153_AU & ci.DisableHorseRacing & ci.DisableOpenTote)
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 1 
		WHERE ci.Enabled = 1                  
	END
	IF @sportType = 161
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			ci.DisableNumber
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustMaster cm WITH(NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 3  
		WHERE ci.Enabled = 1
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			ci.DisableNumber
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustAgent ca WITH(NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 2 
		WHERE ci.Enabled = 1
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			ci.DisableNumber
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 1  
		WHERE ci.Enabled = 1                  
	END
	IF @sportType = 162
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			(~ci.SyncLiveCasino | ci.DisableLiveCasino)
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustMaster cm WITH(NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 3 
		WHERE ci.Enabled = 1    
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			(~ci.SyncLiveCasino | ci.DisableLiveCasino)
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustAgent ca WITH(NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 2 
		WHERE ci.Enabled = 1
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			(~ci.SyncLiveCasino | ci.DisableLiveCasino)
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 1 
		WHERE ci.Enabled = 1            
	END
	
	IF @sportType IN (251)
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			(~ci.SyncCasino |(ci.DisableCasino))
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustMaster cm WITH(NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 3 
		WHERE ci.Enabled = 1   
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			(~ci.SyncCasino |(ci.DisableCasino))
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustAgent ca WITH(NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 2  
		WHERE ci.Enabled = 1 
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			(~ci.SyncCasino |(ci.DisableCasino))
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 1  
		WHERE ci.Enabled = 1       
	END
	IF @sportType = 252
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			(~ci.SyncBingo | ci.DisableBingo)
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustMaster cm WITH(NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 3 
		WHERE ci.Enabled = 1
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			(~ci.SyncBingo | ci.DisableBingo)
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustAgent ca WITH(NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 2
		WHERE ci.Enabled = 1
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			(~ci.SyncBingo | ci.DisableBingo)
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 1 
		WHERE ci.Enabled = 1               
	END
	IF @sportType = 202
    BEGIN      
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			CASE WHEN EXISTS(SELECT TOP 1 1 FROM dbo.CustGameType gt WITH(NOLOCK,INDEX=PK_CustGameType)
																WHERE gt.CustID = ci.CustID AND gt.IsDisabled = 0 ) 
																THEN 0 
																ELSE 1 
																END
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustMaster cm WITH(NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 3
		WHERE ci.Enabled = 1 
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			CASE WHEN EXISTS(SELECT TOP 1 1 FROM dbo.CustGameType gt WITH(NOLOCK,INDEX=PK_CustGameType)
																WHERE gt.CustID = ci.CustID AND gt.IsDisabled = 0 ) 
																THEN 0 
																ELSE 1 
																END
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustAgent ca WITH(NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 2
		WHERE ci.Enabled = 1 
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			CASE WHEN EXISTS(SELECT TOP 1 1 FROM dbo.CustGameType gt WITH(NOLOCK,INDEX=PK_CustGameType)
																WHERE gt.CustID = ci.CustID AND gt.IsDisabled = 0 ) 
																THEN 0 
																ELSE 1 
																END
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 1
		WHERE ci.Enabled = 1              
	END
	--  Gold Deluxe & Metric Gamming
	IF @sportType IN(-1,255,204)
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			CASE WHEN @sportType =255 THEN  ci.DisableGoldDeluxe
				 WHEN @sportType =-1  THEN  ci.DisableSuperLive
				 WHEN @sportType =204 THEN  ci.DisableColossusBet
				 END
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustMaster cm WITH(NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 3 
		WHERE ci.Enabled = 1
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			CASE WHEN @sportType =255 THEN  ci.DisableGoldDeluxe
				 WHEN @sportType =-1  THEN  ci.DisableSuperLive
				 WHEN @sportType =204 THEN  ci.DisableColossusBet
				 END
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustAgent ca WITH(NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 2  
		WHERE ci.Enabled = 1
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			ci.roleid,
			CASE WHEN @sportType =255 THEN  ci.DisableGoldDeluxe
				 WHEN @sportType =-1  THEN  ci.DisableSuperLive
				 WHEN @sportType =204 THEN  ci.DisableColossusBet
				 END
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID AND ci.roleid = 1  
		WHERE ci.Enabled = 1             
	END
	-- Allbet, Macau Games, NG2
	IF @sportType IN (211)
    BEGIN      
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			3,
			1
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustMaster cm WITH(NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID-- AND ci.roleid = 3
		WHERE ci.Enabled = 1 AND ci.roleid = 3
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			2,
			1
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustAgent ca WITH(NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID -- AND ci.roleid = 2
		WHERE ci.Enabled = 1 AND ci.roleid = 2
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			1,
			1
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID-- AND ci.roleid = 1
		WHERE ci.Enabled = 1 AND ci.roleid = 1

		CREATE CLUSTERED INDEX IX_CustID ON #FiltedDownlineAcc (CustID)

		UPDATE fda
		SET fda.IsDisable = A.IsDisable
		FROM #FiltedDownlineAcc fda
			INNER JOIN (SELECT fda.CustID, CASE MIN(CONVERT(INT, f.value)) WHEN 0 THEN 0 ELSE 1 END AS IsDisable
						FROM CustProductStatus cps WITH(NOLOCK)
							INNER JOIN #FiltedDownlineAcc fda ON cps.CustID = fda.CustID
							CROSS APPLY @bitmapOrder b
							CROSS APPLY f_CustSetting_ProductStatusSel(cps.bitmapIsDisabled, b.bitmapOrder) f
						GROUP BY fda.CustID
						) A ON fda.CustID = A.CustID
	END
	-- Macau Games, NG2, Fishing World, Virtual Sports, Lottery, Lucky 3
	IF @sportType IN (212, 213, 219, 220, 180, 160)
    BEGIN      
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			3,
			(SELECT CASE (SELECT value FROM dbo.f_CustSetting_ProductStatusSel(bitmapIsDisabled, @bitmap)) WHEN 0 THEN 0 ELSE 1 END 
							FROM CustProductStatus
							WHERE custid = ci.custid)
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustMaster cm WITH(NOLOCK) ON ci.custid = cm.custid AND cm.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID-- AND ci.roleid = 3
		WHERE ci.Enabled = 1 AND ci.roleid = 3
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			2,
			(SELECT CASE (SELECT value FROM dbo.f_CustSetting_ProductStatusSel(bitmapIsDisabled, @bitmap)) WHEN 0 THEN 0 ELSE 1 END 
							FROM CustProductStatus
							WHERE custid = ci.custid)
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN dbo.CustAgent ca WITH(NOLOCK) ON ci.custid = ca.custid AND ca.IsInternal = 0
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID -- AND ci.roleid = 2
		WHERE ci.Enabled = 1 AND ci.roleid = 2
		
		INSERT INTO #FiltedDownlineAcc
		SELECT sup.CustID,
			ci.custid,
			1,
			(SELECT CASE (SELECT value FROM dbo.f_CustSetting_ProductStatusSel(bitmapIsDisabled, @bitmap)) WHEN 0 THEN 0 ELSE 1 END 
							FROM CustProductStatus
							WHERE custid = ci.custid)
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #FiltedCreditSuper sup ON ci.srecommend = sup.CustID-- AND ci.roleid = 1
		WHERE ci.Enabled = 1 AND ci.roleid = 1
	END
	
	--Return result
	SELECT cust.custid,cust.username,sp.SuperStatus as IsDisable,e.currency,
			ISNULL(rs.MasterEnabled,0)	MasterEnabled,
			ISNULL(rs.MasterDisabled,0) MasterDisabled,
			ISNULL(rs.AgentEnabled,0)	AgentEnabled,
			ISNULL(rs.AgentDisabled,0)	AgentDisabled,
			ISNULL(rs.MemberEnabled,0)	MemberEnabled,
			ISNULL(rs.MemberDisabled,0)	MemberDisabled
	FROM #FiltedCreditSuper sp
	JOIN dbo.Customer cust WITH(NOLOCK) ON cust.custid = sp.CustID 
	JOIN dbo.Exchange e WITH(NOLOCK) ON e.exchangeid = cust.currency
	LEFT JOIN
	(SELECT dl.SuperID,
		SUM(CASE WHEN dl.IsDisable = 0 AND dl.RoleID = 3 THEN 1 ELSE 0 END) MasterEnabled,
		SUM(CASE WHEN dl.IsDisable = 1 AND dl.RoleID = 3 THEN 1 ELSE 0 END) MasterDisabled,
		SUM(CASE WHEN dl.IsDisable = 0 AND dl.RoleID = 2 THEN 1 ELSE 0 END) AgentEnabled,
		SUM(CASE WHEN dl.IsDisable = 1 AND dl.RoleID = 2 THEN 1 ELSE 0 END) AgentDisabled,
		SUM(CASE WHEN dl.IsDisable = 0 AND dl.RoleID = 1 THEN 1 ELSE 0 END) MemberEnabled,
		SUM(CASE WHEN dl.IsDisable = 1 AND dl.RoleID = 1 THEN 1 ELSE 0 END) MemberDisabled
	FROM #FiltedDownlineAcc dl 
	GROUP BY dl.SuperID) rs ON sp.CustID = rs.SuperID
	ORDER BY cust.username,e.currency
	
	--Drop temp tables
	DROP TABLE #FiltedCreditSuper
	DROP TABLE #FiltedDownlineAcc
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_EnableDisableAccount_ByProduct] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_EnableDisableAccount_ByProduct] TO [vnteam] AS [dbo]
GO