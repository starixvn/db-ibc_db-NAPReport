ALTER PROCEDURE [dbo].[Acc_Rpt_TreeWinlost]
	@winlostdate			datetime,
	@roleid					tinyint = 4,
	@custid					int = NULL,
	@WinLost_8RM			money = 0 OUTPUT,
	@VirtualWinLost_8RM		money = 0 OUTPUT,
	@WinLost_BARM			money = 0 OUTPUT,
	@VirtualWinLost_BARM	money = 0 OUTPUT	
AS
/*	Created by: []
	Task: Member Tree Win/Loss
	DB: DB06.BODB02
	Original: Admin_rpt_TreeWinlost

	Revisions:
	- Vinh@20080117: 
		+ Fix get actualrate from bettrans
		+ Add column turnover by virtual rate, total by virtual rate
	- 20090714@Kiwi: Exclude 'Refund' ticket
	- 20100111@Jamie: 
		+ Get currencyName from cache instead of DB
		+ Hide @WinLost_12BETAgent money =0 OUTPUT, @VirtualWinLost_12BETAgent money =0 OUTPUT,
	-- 20100526@Henry: Change to use StatusID instead of Status in WHERE statement
	- 20110516@Lukas: re-arrange bettype
	- 20110822@Elly: - Correct Turnover of sports book since Sep 01, 2011
	- 20120412@Hurri: Get win lost of agent 'BARM'
	- 20120417@Hurri: Move this sp from DBTRANS to DB06
	- 20120423@Hurri: Remove @NegativeBetEffectiveDate='2011-09-01'
	- 20120530@Elodie: Change formula of 8RM/BARM winloss
*/

SET NOCOUNT ON

--DECLARE @NegativeBetEffectiveDate datetime
--SET @NegativeBetEffectiveDate='2011-09-01'

IF @roleid = 4
begin
	SELECT
		i.username, i.custid, b.currency,
		sum(ABS(stake)) TurnOver,
		sum(ABS(stake)*b.actualrate) TurnOverRM,
		sum((1 - spositiontaking - mpositiontaking - apositiontaking)*ABS(stake)) PositionTurnOver,
		sum((1 - spositiontaking - mpositiontaking - apositiontaking)*b.actualrate*ABS(stake)) PositionTurnOverRM,
		sum((swinlost + mwinlost + awinlost + winlost-actual_stake)) Winloss,
		sum(scomm) commission,
		sum((swinlost + mwinlost + awinlost + winlost-actual_stake + scomm)) Total,
		sum((swinlost + mwinlost + awinlost + winlost-actual_stake + scomm)*b.actualrate) TotalRM,
		sum((swinlost + mwinlost + awinlost + winlost-actual_stake + scomm)*b.virtualrate) VirtualTotalRM
	FROM bettrans b with (nolock)
	INNER JOIN custinfo i with (nolock) ON b.srecommend = i.custid AND i.roleid = 4
	WHERE	winlostdate = @winlostdate 
			and bettype < 19001 
			and b.ruben = 1
			--AND b.status NOT IN ('VOID', 'REJECT', 'Refund')
			AND b.statusID NOT IN (101, 102, 103) 
	GROUP BY i.username, i.custid, b.currency
	ORDER BY i.username
	
	-----------------------------------------------------
	---== 12 BET Agent Temporily Hide 
	-----------------------------------------------------
--	SELECT 
--		
--			@WinLost_12BETAgent = ISNULL(SUM(LineTotal),0) ,
--			@VirtualWinLost_12BETAgent = ISNULL(SUM(VirtualLineTotal),0)
--		
--	FROM (
--			SELECT	isnull(sum(-awinlost * bettrans.actualrate) ,0) LineTotal, 
--					isnull(sum(-awinlost * bettrans.virtualrate) ,0)  VirtualLineTotal
--						
--			FROM bettrans  with (nolock)
--			WHERE	bettrans.winlostdate = @winlostdate
--					and bettrans.ruben=1 and bettype < 91 
--					and bettrans.recommend in (
--												791083,	--	12BETUS$01
--												791088,	--	12BETEURO01
--												836210,	--	12BETTB01
--												836215,	--	12BETGBP01
--												836224,	--	12BETRM01
--												836230,	--	12BETRMB01
--												858249,	--	12BETUUS01
--												1015422,--	12BETAUD01
--												1015430	--	12BETCHF01					
--											  )					
--			GROUP BY winlostdate
--				
--			UNION ALL
--
--			SELECT  isnull(sum(-mwinlost * bettrans.actualrate) ,0) LineTotal, 
--					isnull(sum(-mwinlost * bettrans.virtualrate) ,0)  VirtualLineTotal
--			FROM bettrans  with (nolock)
--			WHERE	bettrans.winlostdate = @winlostdate
--					and bettrans.ruben=1 and bettype < 91 
--					and bettrans.recommend in (	
--												860376,	--	12BETUS$02
--												860379,	--	12BETEURO02
--												860380,	--	12BETTB02
--												860383,	--	12BETGBP02
--												860386,	--	12BETRM02
--												860387,	--	12BETRMB02
--												916515,	--	12BETUUS02
--												1015423,--	12BETAUD02
--												1015433	--	12BETCHF02
--											  )						
--			
--			) bettrans
--	
	-----------------------------------------------------
	select @WinLost_8RM = isnull(sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm), 0),
		 @VirtualWinLost_8RM = isnull(sum((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)*bettrans.virtualrate), 0)
	from bettrans with (nolock)
	where
		recommend = 52466 and
		ruben=1 and
		bettype < 20000
		and winlostdate = @winlostdate
		
	-- 20120412@Hurri: Get win lost of agent 'BARM'
	select @WinLost_BARM = isnull(sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm), 0),
		 @VirtualWinLost_BARM = isnull(sum((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)*bettrans.virtualrate), 0)
	from bettrans with (nolock)
	where
		recommend = 5707545 and
		ruben=1 and
		bettype < 20000
		and winlostdate = @winlostdate
	-----------------------------------------------------	
end
ELSE IF @roleid = 3
	SELECT
		i.username, i.custid, b.currency,
		sum(ABS(stake)) TurnOver,
		sum(ABS(stake)*b.actualrate) TurnOverRM,
		sum((1 - mpositiontaking - apositiontaking)*ABS(stake)) PositionTurnOver,
		sum((1 - mpositiontaking - apositiontaking)*b.actualrate*ABS(stake)) PositionTurnOverRM,
		sum(mwinlost + awinlost + winlost-actual_stake) Winloss,
		sum(acomm) commission,
		sum((mwinlost + awinlost + winlost-actual_stake + acomm)) Total,
		sum((mwinlost + awinlost + winlost-actual_stake + acomm)*b.actualrate) TotalRM,
		sum((mwinlost + awinlost + winlost-actual_stake + acomm)*b.virtualrate) VirtualTotalRM				
	FROM bettrans b with (nolock)
	INNER JOIN custinfo i with (nolock) ON b.mrecommend = i.custid AND i.roleid = 3 AND i.srecommend = @custid
	WHERE	winlostdate = @winlostdate 
			and bettype < 19001 
			and ruben = 1
			--AND b.status NOT IN ('VOID', 'REJECT', 'Refund')
			AND b.statusID NOT IN (101, 102, 103) 
	GROUP BY i.username, i.custid, b.currency
	ORDER BY i.username

ELSE IF @roleid = 2
	SELECT
		i.username, i.custid, b.currency,
		sum(ABS(stake)) TurnOver,
		sum(b.actualrate*ABS(stake)) TurnOverRM,
		sum((1 - apositiontaking)*ABS(stake)) PositionTurnOver,
		sum((1 - apositiontaking)*b.actualrate*ABS(stake)) PositionTurnOverRM,		
		sum(awinlost + winlost-actual_stake) Winloss,
		sum(comm) commission,
		sum((awinlost + winlost-actual_stake + comm)) Total,
		sum((awinlost + winlost-actual_stake + comm)*b.actualrate) TotalRM,
		sum((awinlost + winlost-actual_stake + comm)*b.virtualrate) VirtualTotalRM						
	FROM bettrans b with (nolock)
	INNER JOIN custinfo i with (nolock) ON b.recommend = i.custid AND i.roleid = 2 AND i.mrecommend = @custid
	WHERE	winlostdate = @winlostdate 
			and bettype < 19001 
			and ruben = 1
			--AND status NOT IN ('VOID', 'REJECT', 'Refund')
			AND b.statusID NOT IN (101, 102, 103) 
	GROUP BY i.username, i.custid, b.currency
	ORDER BY i.username

ELSE IF @roleid = 1
	SELECT
		i.username, i.custid, b.currency,
		sum(ABS(stake)) TurnOver,
		sum(b.actualrate*ABS(stake)) TurnOverRM,
		sum(ABS(stake)) PositionTurnOver,
		sum(b.actualrate*ABS(stake)) PositionTurnOverRM,		
		sum(winlost-actual_stake) Winloss,
		sum(playercomm) commission,
		sum((winlost-actual_stake + playercomm)) Total,
		sum((winlost-actual_stake + playercomm)*b.actualrate) TotalRM,
		sum((winlost-actual_stake + playercomm)*b.virtualrate) VirtualTotalRM			
	FROM bettrans b with (nolock)
	INNER JOIN custinfo i with (nolock) ON b.custid = i.custid AND i.roleid = 1 AND i.recommend = @custid
	WHERE	winlostdate = @winlostdate 
			and bettype < 19001 
			and ruben = 1
			--AND b.status NOT IN ('VOID', 'REJECT', 'Refund')
			AND b.statusID NOT IN (101, 102, 103) 
	GROUP BY i.username, i.custid,  b.currency
	ORDER BY i.username




GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_TreeWinlost] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_TreeWinlost] TO [VNTeam]
GO 