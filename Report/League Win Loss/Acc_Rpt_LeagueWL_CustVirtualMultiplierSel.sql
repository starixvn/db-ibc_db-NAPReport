/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE Acc_Rpt_LeagueWL_CustVirtualMultiplierSel
	@CustID INT
AS
/*
	Created: 20200818@Jaden
	Task : Get current virtual rate settings of users (cloned from #136629 SMA Winloss)
	DB: DBACC.bodb02

	Revisions:
		20200724@Roy  : NAP Report - SMA Win Loss Summary Report (#136629)
		20200818@Jaden: NAP Report - New drilldown level for League Win Loss (#138955)
		20230313@Jaden: Include Basketball VR (#184708)

	Used by:
		- [DBACC + DBDW] League WL report (by Super)

	Script: EXEC bodb02..Acc_Rpt_LeagueWL_SupVirtualMultiplierSel @CustID=1
*/
BEGIN
	SET NOCOUNT ON
	
	;WITH CTE_currVirtualRate AS (
		SELECT pvs.sporttype
			,pvs.bettype
			,pvs.islive
			,bodb02.dbo.f_GetVirtualSetting(cvs.bitmapVirtual, pvs.profileID) - 1.0 AS virtualMultiplier
		FROM bodb02.dbo.CustVirtualSetting AS cvs WITH (NOLOCK)
		INNER JOIN bodb02.dbo.ProfileVirtualSetting AS pvs WITH (NOLOCK) 
			ON cvs.seqNo = pvs.seqNo
		WHERE cvs.custid = @CustID
			AND pvs.sporttype NOT IN (43) 
			AND pvs.isActive = 1
			AND pvs.bettype in (1,3) --only get Handicap, Over/Under
	)
	SELECT 
		 vm.sporttype AS sportid
		,s.SportName AS sport
		,b.typenamee AS bettype
		,CASE WHEN islive = 1 THEN 'Live' ELSE 'Non-Live' END AS islive
		,vm.virtualMultiplier AS virtualMultiplier
	FROM CTE_currVirtualRate vm
	INNER JOIN bodb02.dbo.Sports s WITH (NOLOCK) 
		ON vm.sporttype = s.SportType
	INNER JOIN bodb02.dbo.BetType b WITH (NOLOCK) 
		ON vm.bettype = b.typeid
	ORDER BY sportid, isLive, bettype
	OPTION (RECOMPILE)
END
