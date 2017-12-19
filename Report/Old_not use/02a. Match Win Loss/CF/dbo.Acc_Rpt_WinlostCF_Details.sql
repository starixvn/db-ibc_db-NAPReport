USE [bodb02]
GO
 
ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostCF_Details]
	@WinlostDate	DATETIME,
	@ArenaId		INT
AS 
/*	
	Creator:20160229@Jim
	Task: Report 2a for Cock Fighting
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
	
	;WITH cte_Fight
	AS
		(
		SELECT  EventInfo3rdId
				,ArenaID
				,FightNo
				,EventDate
				--,CONVERT (VARCHAR(512),HomeOwner) +'-vs-'+CONVERT(VARCHAR(512),AwayOwner) AS [Match]
				,HomeOwner
				,AwayOwner
		FROM dbo.EventInfo3rd  WITH (NOLOCK)	
		WHERE ArenaID = @ArenaID	
			  AND EventDate = @WinlostDate
		)
		,
	cte_bettrans
	AS
		(
	SELECT 
		  betdaqid
		  ,betcheck
		  ,winlostdate	
		 ,ISNULL(SUM ((winlost - actual_stake) * b.actualrate), 0) WinLoss
		 ,ISNULL(SUM ((awinlost + mwinlost + swinlost) * b.actualrate), 0) Position
		 ,ISNULL(SUM (scomm * b.actualrate), 0) Commission
		 ,ISNULL(SUM (scomm*virtualrate), 0) VirtualCommission
		 ,ISNULL(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate),0)as RealLineTotal
		 ,ISNULL(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*virtualrate),0) as VirtualLineTotal
		 ,ISNULL(sum((1-tpositiontaking)*abs(stake)*actualrate),0) as RealTurnover
	FROM dbo.bettrans  b WITH (NOLOCK)
		INNER JOIN @tblBettype bet ON b.bettype = bet.bettypeID
	WHERE b.Winlostdate = @WinlostDate
		  AND b.ruben = 1
		  AND b.statusID NOT IN (101, 102, 121)
	GROUP BY   betdaqid
			  ,betcheck
			  ,winlostdate	
		)
	SELECT 	 c.FightNo
			 ,c.HomeOwner
			 ,c.AwayOwner 
			,SUM(WinLoss) AS WinLoss
			,SUM(Position) AS Position
			,SUM(Commission) AS Commission
			,SUM(VirtualCommission) AS VirtualCommission
			,SUM(RealLineTotal) AS RealLineTotal
			,SUM(VirtualLineTotal) AS VirtualLineTotal
			,SUM (RealTurnover) AS RealTurnover
	FROM cte_bettrans b
		INNER JOIN cte_fight c ON   CONVERT(INT, b.betcheck) = c.ArenaID
														AND CONVERT(INT, b.betdaqid) = c.FightNo
														AND b.winlostdate = c.EventDate		
    GROUP BY   c.FightNo
			 ,c.HomeOwner
			 ,c.AwayOwner 															
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostCF_Details] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostCF_Details] TO [VNTeam]
GO		 