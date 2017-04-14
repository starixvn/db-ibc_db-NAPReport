ALTER PROCEDURE [dbo].[Acc_Rpt_MatchWinLoss2_Sporttype] @winlostdate   DATETIME,
                                                              @Sporttype     NVARCHAR(100) = '',
                                                              @Bettype       INT           = 0,
                                                              @LiveIndicator BIT           = 0
AS
	
/*	Creator: Elodie	
		Date: 20120827
		Task: Report winlost by sport type and bet type
		DB: DB06.BODB02		
	
		History:
			- 20121009@Elodie: Add 34 new bettypes of Tennis (1301 -> 1334)
			- 20130311@Don: Add column [IBC Turnover] into resultset
			- 20141203@Dom: Apply sport bettype matrix
			- 20160408@Robert: Support drill-down to the match winloss details for Megic Gaming - Superlive product [RedmineID#55584], this sp only used for Megic Gaming - Superlive product

		Explanation's Param:
			 - @Sporttype: not use but have to retain to same with the structure on DW

	*/

     BEGIN
         SET NOCOUNT ON;
         SELECT b.bettype,
                b.liveindicator,
                m.matchcode,
                m.kickofftime,
                --      b.matchid,
                m.homeid,
                m.awayid,
                ISNULL(m.isNeutral, CONVERT( BIT, 0)) AS IsNeutral,
                SUM((winlost - actual_stake) * actualrate) winlost,
                SUM((awinlost + mwinlost + swinlost) * actualrate) pos,
                SUM((scomm) * actualrate) comm,
                SUM((scomm) * virtualrate) VirtualComm,
                SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS LineTotal,
                SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * virtualrate) AS VirtualLineTotal,
                SUM((1 - tpositiontaking) * ABS(stake) * actualrate) IBCTurnover
         FROM bettrans b WITH (nolock)
              INNER JOIN match m WITH (nolock) ON m.matchid = b.matchid
         WHERE winlostdate = @winlostdate
               AND b.ruben = 1
               AND b.statusID NOT IN(101, 102, 103)
              AND b.bettype = @Bettype
              AND b.liveindicator = @LiveIndicator
         GROUP BY b.bettype,
                  b.liveindicator,
                  m.matchcode,
                  m.kickofftime,
                  m.homeid,
                  m.awayid,
                  m.isNeutral
         ORDER BY m.matchcode;
     END;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_MatchWinLoss2_Sporttype] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_MatchWinLoss2_Sporttype] TO [vnteam];