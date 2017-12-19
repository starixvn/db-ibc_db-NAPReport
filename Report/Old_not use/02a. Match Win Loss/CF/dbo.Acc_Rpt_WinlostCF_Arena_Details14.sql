ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostCF_Arena_Details14]
	@ArenaID		int = 0,
	@winlostdate	datetime
AS
/*	Creator: Percy
	Date: 2015-12-15
	Task: Report 2A/2H for Cockfighting
	DB:  DBACC/bodb02
	Original: 
	
	Revisions:
		- 20151215@Percy: Support Cockfighting [Redmine: #49027]
	
	Explanation's Param:

*/
BEGIN
SET NOCOUNT ON

IF @ArenaID = 0 -- get all Arena
BEGIN
	SELECT	FightNo,
			ArenaID,
			HomeOwner,
			AwayOwner,
			isnull(sum((winlost-actual_stake)*actualrate),0)  WinLoss,
			isnull(sum((awinlost+mwinlost+swinlost)*actualrate),0) Position,
			isnull(sum(scomm*actualrate),0) Commission,
			isnull(sum(scomm*actualrate),0) VirtualCommission,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate),0) as RealLineTotal,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate),0) as VirtualLineTotal,
			isnull(sum((1-tpositiontaking) * ABS(stake) * actualrate),0) RealTurnover
	FROM	bettrans14 b WITH (NOLOCK)
	INNER JOIN EventInfo3rd14 e WITH (NOLOCK)
		ON CONVERT(INT, b.betcheck) = e.ArenaID
			AND CONVERT(INT, b.betdaqid) = e.FightNo
			AND b.winlostdate = e.EventDate
	WHERE	winlostdate = @winlostdate 
			AND ruben = 1
			AND bettype = 1003
			AND matchid = 206
			AND statusID NOT IN (101,102,121)
			--AND betcheck = CONVERT(NVARCHAR(100), @ArenaID)
			--AND ArenaID = @ArenaID
	GROUP BY
		FightNo,
		ArenaID,
		HomeOwner,
		AwayOwner
	ORDER BY
		FightNo,
		ArenaID
END
ELSE
BEGIN
	SELECT	FightNo,
			ArenaID,
			HomeOwner,
			AwayOwner,
			isnull(sum((winlost-actual_stake)*actualrate),0)  WinLoss,
			isnull(sum((awinlost+mwinlost+swinlost)*actualrate),0) Position,
			isnull(sum(scomm*actualrate),0) Commission,
			isnull(sum(scomm*actualrate),0) VirtualCommission,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate),0) as RealLineTotal,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate),0) as VirtualLineTotal,
			isnull(sum((1-tpositiontaking) * ABS(stake) * actualrate),0) RealTurnover
	FROM	bettrans14 b WITH (NOLOCK)
	INNER JOIN EventInfo3rd14 e WITH (NOLOCK)
		ON CONVERT(INT, b.betcheck) = e.ArenaID
			AND CONVERT(INT, b.betdaqid) = e.FightNo
			AND b.winlostdate = e.EventDate
	WHERE	winlostdate = @winlostdate 
			AND ruben = 1
			AND bettype = 1003
			AND matchid = 206
			AND statusID NOT IN (101,102,121)
			--AND betcheck = CONVERT(NVARCHAR(100), @ArenaID)
			AND ArenaID = @ArenaID
	GROUP BY
		FightNo,
		ArenaID,
		HomeOwner,
		AwayOwner
	ORDER BY
		FightNo,
		ArenaID
END
END
GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostCF_Arena_Details14] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostCF_Arena_Details14] TO [bodbAdminNet]
GO