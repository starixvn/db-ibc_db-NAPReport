ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Details]
	@winlostdate	datetime,
	@SportType		int = 1,
	@liveindicator	bit,
	@bettype		int,
	@IsHedge		bit = 0
AS

	/*	Creator: Phuong Dao
		Date: 2009-02-26
		Task: Detailed Winloss Summary History
		DB: DBACC/bodb02
		
		Revisions:
			- 200907013@Kiwi: Exclude 'Refund' Ticket
			- 20090731@Jamie: Not to view data in range of date, but only one date at once 				
			-- 20100525@Henry: Change to use StatusID instead of Status in WHERE statement
			16Dec2010@Viet: Correct Turnover's value, will revert back when old data's gone
			- 20110516@Lukas: re-arrange bettype
			- 20110824@Johnson: remove check winlostdate with '16 Dec 2010' for sumary turnover, get from stake instead actual_stake
			- 20110822@Elly: - Correct Turnover of sports book since Sep 01, 2011
			- 20120412@Hurri: Get win lost of agent 'BARM' (@WinLost_BARM)
			- 20120423@Hurri: Remove @NegativeBetEffectiveDate='2011-09-01'
			- 20120530@Elodie: Change formula of 8RM/BARM winloss
			- 20121102@Elodie: Use actual rate instead of virtural rate for Virtual sport
			- 20130220@Elodie: Add range of Virtual Sport (180 -> 186)
			- 20130307@Elodie: Remove Virtual HR from Virtual Sport (Virtual HR uses the other SP)
			- 20130408@Elodie: Add RealLineTotal field for all products that enable virtual currency
			- 20130506@Elodie: Get matchid value
			- 20130522@Elodie: Get more fields RealTurnover, VirtualTurnover
			- 20150209@Johnson: get more fields for 8RM and BARM [redmine: #27216]
	*/	

	SET NOCOUNT ON
	--DECLARE @NegativeBetEffectiveDate datetime
	--SET @NegativeBetEffectiveDate='2011-09-01'
	
	IF @bettype <> 10
	BEGIN
		IF(@IsHedge = 1)
		BEGIN
			SELECT
					b.matchid,
					m.matchcode,
					m.HomeId,
					m.AwayId,
					b.liveindicator,
					b.BetType bType, 
					m.leagueid,					
					sum((winlost-actual_stake)*virtualrate) WinLost,
					sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
					sum(scomm*virtualrate) Commission,
					sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
					sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
					sum((1-tpositiontaking)*ABS(b.stake)*actualrate) RealTurnover,
					sum((1-tpositiontaking)*ABS(b.stake)*virtualrate) VirtualTurnover,
					isnull(m.isNeutral, CONVERT(BIT,0)) as IsNeutral
			FROM 
					bettrans b with (nolock)
					INNER JOIN match m with (nolock) ON b.matchid = m.matchid
			WHERE
					winlostdate = @winlostdate
					AND b.bettype < 19001
					AND b.matchid > 0
					--AND status NOT IN ('VOID', 'REJECT', 'Refund') AND b.ruben = 1			
					AND statusID NOT IN (102, 101, 103) AND b.ruben = 1			
					AND m.SportType = @SportType
					AND b.BetType = @Bettype
					AND b.liveindicator = @liveindicator			
					AND matchcode like '%hedge%'
			GROUP BY
					b.matchid,
					m.matchcode,
					m.HomeId,
					m.AwayId,
					b.liveindicator,
					b.bettype, 
					m.leagueid,
					m.isNeutral
			ORDER BY 
					bType, 
					m.leagueid,--leaguename,
					m.matchcode, 
					m.HomeId
			
		END
		ELSE IF (@IsHedge = 0)
		BEGIN
			IF @SportType IN (180, 182, 183, 184, 185, 186)  -- Virtual sport but Virtual HR
			BEGIN
				SELECT
						b.matchid,
						m.matchcode,
						m.HomeId,
						m.AwayId,
						b.liveindicator,
						b.BetType bType, 
						m.leagueid,					
						sum((winlost-actual_stake)*actualrate) WinLost,
						sum((awinlost+mwinlost+swinlost)*actualrate) Position,
						sum(scomm*actualrate) Commission,
						sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
						sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
						sum((1-tpositiontaking)*ABS(b.stake)*actualrate) RealTurnover,
						0 VirtualTurnover,
						isnull(m.isNeutral, CONVERT(BIT,0)) as IsNeutral
				FROM 
						bettrans b with (nolock)
						INNER JOIN match m with (nolock) ON b.matchid = m.matchid
				WHERE
						b.winlostdate = @winlostdate
						AND b.bettype < 19001
						--AND status NOT IN ('VOID', 'REJECT', 'Refund') 
						AND statusID NOT IN (102, 101, 103) 
						AND b.matchid > 0 
						AND b.ruben = 1			
						AND m.SportType = @SportType
						AND b.BetType = @Bettype
						AND b.liveindicator = @liveindicator	
						AND m.matchcode not like '%hedge%'		
				GROUP BY
						b.matchid,
						m.matchcode,
						m.HomeId,
						m.AwayId,
						b.liveindicator,
						b.bettype, 
						m.leagueid,
						m.isNeutral
				ORDER BY 
						bType, 
						m.leagueid,--leaguename,
						m.matchcode, 
						m.HomeId
			END
			ELSE
			BEGIN
				SELECT
						b.matchid,
						m.matchcode,
						m.HomeId,
						m.AwayId,
						b.liveindicator,
						b.BetType bType, 
						m.leagueid,					
						sum((winlost-actual_stake)*virtualrate) WinLost,
						sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
						sum(scomm*virtualrate) Commission,
						sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
						sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
						sum((1-tpositiontaking)*ABS(b.stake)*actualrate) RealTurnover,
						sum((1-tpositiontaking)*ABS(b.stake)*virtualrate) VirtualTurnover,
						isnull(m.isNeutral, CONVERT(BIT,0)) as IsNeutral
				FROM 
						bettrans b with (nolock)
						INNER JOIN match m with (nolock) ON b.matchid = m.matchid
				WHERE
						b.winlostdate = @winlostdate
						AND b.bettype < 19001
						--AND status NOT IN ('VOID', 'REJECT', 'Refund') 
						AND statusID NOT IN (102, 101, 103) 
						AND b.matchid > 0 
						AND b.ruben = 1			
						AND m.SportType = @SportType
						AND b.BetType = @Bettype
						AND b.liveindicator = @liveindicator	
						AND m.matchcode not like '%hedge%'		
				GROUP BY
						b.matchid,
						m.matchcode,
						m.HomeId,
						m.AwayId,
						b.liveindicator,
						b.bettype, 
						m.leagueid,
						m.isNeutral
				ORDER BY 
						bType, 
						m.leagueid,--leaguename,
						m.matchcode, 
						m.HomeId
			END
		END
	END
	ELSE
	BEGIN
		SELECT
				b.matchid,
				o.matchcode,
				o.TeamId as HomeId,
				0 as AwayId,
				0 liveindicator,
				b.BetType bType, 
				l.leagueid,
				sum((winlost-actual_stake)*virtualrate) WinLost,
				sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
				sum(scomm*virtualrate) Commission,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
				sum((1-tpositiontaking)*ABS(b.stake)*actualrate) RealTurnover,
				sum((1-tpositiontaking)*ABS(b.stake)*virtualrate) VirtualTurnover,
				CONVERT(BIT,0) as IsNeutral
		FROM
				bettrans b with (nolock)
				INNER JOIN outright o with (nolock) ON b.matchid = o.orid
				INNER JOIN league l with (nolock) ON o.leagueid = l.leagueid
				INNER JOIN sports sp with (nolock) ON l.sporttype = sp.sporttype
		WHERE
				winlostdate = @winlostdate
				--AND b.status NOT IN ('VOID', 'REJECT', 'Refund') AND b.ruben = 1	
				AND b.statusID NOT IN (102, 101, 103) AND b.ruben = 1	
				AND b.matchid > 0 				
				AND sp.SportType = @SportType
				AND b.bettype = 10
		GROUP BY
				b.matchid,
				o.matchcode,
				o.TeamId,
				b.bettype, 
				l.leagueid
		ORDER BY 
				bType, 
				leagueid,--leaguename,
				o.matchcode, 
				HomeId
	END	

	SELECT	1 as ibc,--8RM
			-sum(winlost-actual_stake) WinLost,
			-sum(awinlost+mwinlost+swinlost) Position,
			sum(scomm) Commission,	
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) RealLineTotal,
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) VirtualLineTotal,
			-sum((1-tpositiontaking)*ABS(stake)) RealTurnover,
			-sum((1-tpositiontaking)*ABS(stake)) VirtualTurnover
	FROM	bettrans b WITH (NOLOCK)
			INNER JOIN
			(
				select matchid, leagueid, exrisk from match with (nolock)
				union all
				select orid, leagueid, 0 from outright with (nolock)
			) m ON b.matchid = m.matchid
			INNER JOIN league l with (nolock) ON m.leagueid = l.leagueid
			INNER JOIN sports sp with (nolock) ON l.sporttype = sp.sporttype
	WHERE
			b.winlostdate = @winlostdate
			--AND b.status NOT IN ('VOID', 'REJECT','REFUND') 
			AND b.statusID NOT IN (102, 101,103) 
			AND b.ruben = 1
			AND b.matchid > 0
			AND sp.SportType = @SportType
			AND m.ExRisk = 0
			AND b.liveindicator = @liveindicator		
			AND b.recommend = 52466		
			AND b.BetType = @Bettype
			
	-- 20120412@Hurri: Get win lost of agent 'BARM' (@WinLost_BARM)
	SELECT	2 as ibc,--BARM
			-sum(winlost-actual_stake) WinLost,
			-sum(awinlost+mwinlost+swinlost) Position,
			sum(scomm) Commission,	
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) RealLineTotal,
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) VirtualLineTotal,
			-sum((1-tpositiontaking)*ABS(stake)) RealTurnover,
			-sum((1-tpositiontaking)*ABS(stake)) VirtualTurnover
	FROM	bettrans b WITH (NOLOCK)
			INNER JOIN
			(
				select matchid, leagueid, exrisk from match with (nolock)
				union all
				select orid, leagueid, 0 from outright with (nolock)
			) m ON b.matchid = m.matchid
			INNER JOIN league l with (nolock) ON m.leagueid = l.leagueid
			INNER JOIN sports sp with (nolock) ON l.sporttype = sp.sporttype
	WHERE
			b.winlostdate = @winlostdate
			--AND b.status NOT IN ('VOID', 'REJECT','REFUND') 
			AND b.statusID NOT IN (102, 101,103) 
			AND b.ruben = 1
			AND b.matchid > 0
			AND sp.SportType = @SportType
			AND m.ExRisk = 0
			AND b.liveindicator = @liveindicator		
			AND b.recommend = 5707545		
			AND b.BetType = @Bettype
-------------------

GO
GRANT EXECUTE ON dbo.[Acc_Rpt_DailyWLDirect_Details] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_Details] TO [vnteam]