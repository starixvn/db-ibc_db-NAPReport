USE [bodb02]
GO
 
ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostCF14]
	@WinlostDate	DATETIME 
AS 
/*	
	Creator:20160229@Jim
	Task: Report 2a for CockFighting
	DB:  DBACC/bodb02
	Original: 
	
	Revisions :
			 
	Explanation's Param:

*/
	SET NOCOUNT ON
 
	
	DECLARE @tblBettype AS TABLE (bettypeID INT)
	INSERT INTO @tblBettype (bettypeID )
	SELECT bettype
	FROM dbo.SportBettypeMatrix WITH (NOLOCK)
	WHERE ProductID=19
	
	SELECT
		e.ArenaId
		,l.leaguename 
		,SUM(winloss) AS winloss
		,SUM(Position) AS Position
		,SUM(Commission) AS Commission
		,SUM(VirtualCommission) AS VirtualCommission
		,SUM (RealLineTotal) AS RealLineTotal
		,SUM(VirtualLineTotal) AS VirtualLineTotal
		,SUM(RealTurnover) AS RealTurnover
	FROM	
		(SELECT 
				b.betcheck
				,b.betdaqid
				,winlostdate
				,ISNULL(SUM ((winlost - actual_stake) * b.actualrate), 0) winloss  
			   ,ISNULL(SUM ((awinlost + mwinlost + swinlost) * b.actualrate), 0) Position  
			   ,ISNULL(SUM (scomm * b.actualrate), 0) Commission  
			   ,ISNULL(SUM (scomm*virtualrate), 0) VirtualCommission  
			   ,ISNULL(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate),0)as RealLineTotal  
			   ,ISNULL(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate),0) as VirtualLineTotal  
			   ,ISNULL(sum((1-tpositiontaking)*abs(stake)*actualrate),0) as RealTurnover  
		 FROM dbo.bettrans14 b WITH (NOLOCK)  
			  INNER JOIN  @tblBettype bet ON b.bettype = bet.bettypeID  
		 WHERE    
			b.Winlostdate = @WinlostDate  
			AND b.ruben = 1  
			AND b.statusID NOT IN (101, 102, 121)  
		 GROUP BY b.betcheck
				,b.betdaqid
				,winlostdate
				  
				
		 ) b
 INNER JOIN dbo.EventInfo3rd14 e WITH (NOLOCK) ON CONVERT(INT, b.betcheck) = e.ArenaID
													AND CONVERT(INT, b.betdaqid) = e.FightNo
													AND b.winlostdate = e.EventDate
INNER JOIN dbo.league l WITH (NOLOCK) ON e.ArenaID = l.leagueid 													
GROUP BY 	e.ArenaId
			,l.leaguename 												
			
 ORDER BY l.leaguename  

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostCF14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostCF14] TO [VNTeam]
GO