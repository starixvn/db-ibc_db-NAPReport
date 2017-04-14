ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostMG_Details] @WinlostDate DATETIME,
                                                  @SubProduct  VARCHAR(500) = 'MG-SuperLive'
AS 

/*	
	Creator:20150520@Sophia
	Task: Report 2a for Metrix Gaming 
	DB:  DBACC/bodb02
	Original: 
	
	Revisions :
			 - 20160408@Robert: Support drill-down to the match winloss details for Megic Gaming - Superlive product [RedmineID#55584], get more column b.liveindicator
	Explanation's Param:

*/

     SET NOCOUNT ON;

     ----Get Sport Bettype Matrix------
     DECLARE @isTest BIT= 0;
     SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
     DECLARE @SportBettype TABLE
     (ProductID  INT,
      Bettype    INT,
      EventType  INT,
      SubProduct VARCHAR(500)
     );
     INSERT INTO @SportBettype
            SELECT ProductID,
                   Bettype,
                   EventType,
                   SubProduct
            FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest);
     SELECT b.bettype,
            b.liveindicator,
            ISNULL(SUM((1 - tpositiontaking) * ABS(stake) * actualrate), 0) Turnover,
            ISNULL(SUM((winlost - actual_stake) * b.actualrate), 0) winlost,
            ISNULL(SUM((awinlost + mwinlost + swinlost) * b.actualrate), 0) pos,
            ISNULL(SUM(scomm * b.actualrate), 0) comm,
		  ISNULL(SUM(scomm * b.virtualrate), 0) VirtualCommission,
            ISNULL(SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * b.actualrate), 0) AS LineTotal,
		  ISNULL(SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * b.virtualrate), 0) AS VirtualLineTotal
     FROM dbo.bettrans b WITH (NOLOCK)
          INNER JOIN @SportBettype s ON b.Bettype = s.Bettype
     WHERE s.ProductID = 1
           AND s.SubProduct = @SubProduct
           AND b.Winlostdate = @WinlostDate
           AND b.ruben = 1
           AND b.statusID NOT IN(101, 102, 121)
     GROUP BY b.bettype,
              b.liveindicator
     ORDER BY b.bettype;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostMG_Details] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostMG_Details] TO [vnteam];