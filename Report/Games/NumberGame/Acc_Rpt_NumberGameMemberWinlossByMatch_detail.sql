ALTER PROCEDURE [dbo].[Acc_Rpt_NumberGameMemberWinlossByMatch_details]
 @date smalldatetime,
 @matchid int,
 @bettype smallint,
 @islive bit
AS
/*
Created: 20101217@Viet
Task: Get Number Game report - member w/l by match (by bettype)
DB: DBACC/bodb02
  
Revisions:
	- 20120215@Elodie: Change linked server DB06 to DBARC
*/  
  
SET NOCOUNT ON  

IF @@SERVERNAME = '5WRHH1S' -- FOR LOCAL TESTING PURPOSE (server 211)
BEGIN
	SELECT 
		custid,
		Username, 
		isnull(sum(stake*actualrate),0) turnover,
		isnull(sum(scomm/(1-tpositiontaking)*actualrate),0) grosscomm,		
		isnull(sum((winlost-actual_stake)*actualrate), 0) memberwinlost,
		isnull(sum(playercomm*actualrate), 0) membercomm,
		isnull(sum((winlost-actual_stake+playercomm)*actualrate), 0) membertotal,
		isnull(sum(awinlost*actualrate), 0) agwinlost,		
		isnull(sum((comm-playercomm)*actualrate),0) agentcomm,
		isnull(sum((awinlost+comm-playercomm)*actualrate), 0) agenttotal,			
		isnull(sum(mwinlost*actualrate),0) masterwinlost,
		isnull(sum((acomm-comm)*actualrate),0) mastercomm,
		isnull(sum((mwinlost+acomm-comm)*actualrate),0) mastertotal,
		isnull(sum(swinlost*actualrate),0) superwinlost,
		isnull(sum((scomm-acomm)*actualrate),0) supercomm,
		isnull(sum((swinlost-scomm-acomm)*actualrate),0) supertotal,
		isnull(sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate), 0) company
	FROM bettrans with(nolock)
	WHERE matchid = 928282
		and bettype = @bettype
		and liveindicator = @islive
	group by custid, username, actualrate
	order by custid
END
ELSE
BEGIN
	DECLARE @BalanceUpDay smalldatetime, @MoveBetsDay smalldatetime
	SELECT @MoveBetsDay = max(winlostdate), @BalanceUpDay = min(winlostdate) FROM Bettrans14 WITH(NOLOCK)  

	IF @date > @MoveBetsDay -- bettrans
	BEGIN
		SELECT 
			custid,
			Username, 
			isnull(sum(stake*actualrate),0) turnover,
			isnull(sum(scomm/(1-tpositiontaking)*actualrate),0) grosscomm,		
			isnull(sum((winlost-actual_stake)*actualrate), 0) memberwinlost,
			isnull(sum(playercomm*actualrate), 0) membercomm,
			isnull(sum((winlost-actual_stake+playercomm)*actualrate), 0) membertotal,
			isnull(sum(awinlost*actualrate), 0) agwinlost,		
			isnull(sum((comm-playercomm)*actualrate),0) agentcomm,
			isnull(sum((awinlost+comm-playercomm)*actualrate), 0) agenttotal,			
			isnull(sum(mwinlost*actualrate),0) masterwinlost,
			isnull(sum((acomm-comm)*actualrate),0) mastercomm,
			isnull(sum((mwinlost+acomm-comm)*actualrate),0) mastertotal,
			isnull(sum(swinlost*actualrate),0) superwinlost,
			isnull(sum((scomm-acomm)*actualrate),0) supercomm,
			isnull(sum((swinlost-scomm-acomm)*actualrate),0) supertotal,
			isnull(sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate), 0) company
		FROM bettrans with(nolock)
		WHERE winlostdate = @date
			and matchid = @matchid
			and bettype = @bettype
			and liveindicator = @islive
			and statusID in (111,112,113)
		group by custid, username, actualrate
		order by custid		

	END
	ELSE IF @date > @BalanceUpDay -- bettrans14
	BEGIN
		SELECT 
			custid,
			Username, 
			isnull(sum(stake*actualrate),0) turnover,
			isnull(sum(scomm/(1-tpositiontaking)*actualrate),0) grosscomm,		
			isnull(sum((winlost-actual_stake)*actualrate), 0) memberwinlost,
			isnull(sum(playercomm*actualrate), 0) membercomm,
			isnull(sum((winlost-actual_stake+playercomm)*actualrate), 0) membertotal,
			isnull(sum(awinlost*actualrate), 0) agwinlost,		
			isnull(sum((comm-playercomm)*actualrate),0) agentcomm,
			isnull(sum((awinlost+comm-playercomm)*actualrate), 0) agenttotal,			
			isnull(sum(mwinlost*actualrate),0) masterwinlost,
			isnull(sum((acomm-comm)*actualrate),0) mastercomm,
			isnull(sum((mwinlost+acomm-comm)*actualrate),0) mastertotal,
			isnull(sum(swinlost*actualrate),0) superwinlost,
			isnull(sum((scomm-acomm)*actualrate),0) supercomm,
			isnull(sum((swinlost-scomm-acomm)*actualrate),0) supertotal,
			isnull(sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate), 0) company
		FROM bettrans14 with(nolock)
		WHERE winlostdate = @date
			and matchid = @matchid
			and bettype = @bettype
			and liveindicator = @islive
			and statusID in (111,112,113)
		group by custid, username, actualrate
		order by custid		
	END
	ELSE --bettrans_bk
	BEGIN
		SELECT 
			b.custid,
			Username, 
			isnull(sum(stake*actualrate),0) turnover,
			isnull(sum(scomm/(1-tpositiontaking)*actualrate),0) grosscomm,		
			isnull(sum((winlost-actual_stake)*actualrate), 0) memberwinlost,
			isnull(sum(playercomm*actualrate), 0) membercomm,
			isnull(sum((winlost-actual_stake+playercomm)*actualrate), 0) membertotal,
			isnull(sum(awinlost*actualrate), 0) agwinlost,		
			isnull(sum((comm-playercomm)*actualrate),0) agentcomm,
			isnull(sum((awinlost+comm-playercomm)*actualrate), 0) agenttotal,			
			isnull(sum(mwinlost*actualrate),0) masterwinlost,
			isnull(sum((acomm-comm)*actualrate),0) mastercomm,
			isnull(sum((mwinlost+acomm-comm)*actualrate),0) mastertotal,
			isnull(sum(swinlost*actualrate),0) superwinlost,
			isnull(sum((scomm-acomm)*actualrate),0) supercomm,
			isnull(sum((swinlost-scomm-acomm)*actualrate),0) supertotal,
			isnull(sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate), 0) company
		FROM DBARC.bodb_archive.dbo.bettrans_bk b with(nolock)
			inner join custinfo c with(nolock) on b.custid = c.custid
		WHERE winlostdate = @date
			and matchid = @matchid
			and bettype = @bettype
			and liveindicator = @islive
			and statusID in (111,112,113)
		group by b.custid, username, actualrate
		order by b.custid		
	END
END
  
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_NumberGameMemberWinlossByMatch_details] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NumberGameMemberWinlossByMatch_details] TO [vnteam]
GO