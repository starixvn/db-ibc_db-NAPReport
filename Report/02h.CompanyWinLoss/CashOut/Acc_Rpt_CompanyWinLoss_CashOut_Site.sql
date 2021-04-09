/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_CashOut_Site 
	@StartDate SMALLDATETIME, 
    @EndDate   SMALLDATETIME, 
    @Site      VARCHAR(50),
    @IsLive    INT           = 2
AS

/*
Creator: 20170418@Jacob
DB: DBACC/bodb02
Revisions:
	20170418@Jacob: Integrate Cash Out - Redmine:#73419
	2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
	20181018@Robert: Fix performance issue on House Win Loss by Product [#103309]
	20190925@Jacob: Group By CN88 (#118824)
	20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
	20200320@Cherry: Support deadball Cash Out (#130302)
    20212203@Jaden: Support SABA789 (#151326)

Parameter's Explanation:
	- @Site: credit, deposit
Example:

EXEC [Acc_Rpt_CompanyWinLoss_CashOut_Site] @StartDate='2016-08-24', @EndDate='2020-01-01', @Site = 'Deposit',@IsLive = 2
*/

     SET NOCOUNT ON;
    BEGIN -- #Agent

        CREATE TABLE #DepositSuper (CustId INT PRIMARY KEY);
        INSERT INTO #DepositSuper
            SELECT custid FROM DBWH.bodb_Account.dbo.vw_Dep_CustSuper WITH (NOLOCK);

        CREATE TABLE #Agent
        (CustId INT
         PRIMARY KEY, 
         Site   VARCHAR(50)
        )
        IF @Site = 'CN88'
            BEGIN
                INSERT INTO #Agent
                       SELECT c.CustId, 
                              c.Site
                       FROM customer AS c WITH(NOLOCK)
                            INNER JOIN CS_CustSuper cn88 WITH(NOLOCK) ON c.srecommend = cn88.CustId
                       WHERE c.RoleID = 2;
        END;
            ELSE
            IF @Site = 'Deposit'
                BEGIN
                    INSERT INTO #Agent
                           SELECT c.CustId, 
                                  c.Site
                           FROM customer AS c WITH(NOLOCK)
                                INNER JOIN #DepositSuper AS dep WITH(NOLOCK) ON c.srecommend = dep.CustId
                           WHERE c.RoleID = 2
                                 AND c.CustId NOT IN(52466, 5707545);
                    INSERT INTO #Agent
                           SELECT 5707545, 
                                  'BEST-ODDS';
            END;
                ELSE
                BEGIN
                    INSERT INTO #Agent
                           SELECT c.CustId, 
                                  c.Site
                           FROM customer AS c WITH(NOLOCK)
                                LEFT JOIN #DepositSuper AS dep WITH(NOLOCK) ON c.srecommend = dep.CustId
                                LEFT JOIN CS_CustSuper cn88 WITH(NOLOCK) ON c.srecommend = cn88.CustId
                           WHERE c.RoleID = 2
                                 AND c.CustId NOT IN(52466, 5707545)
                                AND dep.CustId IS NULL
                                AND cn88.CustId IS NULL;
                    INSERT INTO #Agent
                           SELECT 52466, 
                                  'XYZBET';--8RM;
            END
    END
    
    CREATE TABLE #Data
        (RowName         NVARCHAR(50), 
         MemberWinLoss   MONEY, 
         SMAWinLoss      MONEY, 
         ExtraPT         MONEY, 
         Commission      MONEY, 
         RealIncome      MONEY, 
         RealTurnover    MONEY
        )
    
    INSERT INTO #Data
	SELECT ag.site AS RowName, 
		  SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss, 
		  SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
		  SUM(CASE
				  WHEN b.tpositiontaking = 1
				  THEN 0
				  ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
			  END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT, 
		  SUM(scomm * actualrate) AS Commission, 
		  SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
																					 WHEN tpositiontaking = 1
																					 THEN 0
																					 ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																				 END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome, 	  
		  SUM(CASE
				  WHEN tpositiontaking = 1
				  THEN 0
				  ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * CASE
																						  WHEN virtualrate > actualrate
																						  THEN virtualrate
																						  ELSE actualrate
																					  END
			  END) AS RealTurnover
	FROM bettrans AS b WITH(NOLOCK)
			INNER JOIN #Agent AS ag ON b.recommend = ag.custid
	WHERE b.winlostdate = @StartDate
			 AND b.bettype IN (913,914)
			 AND (@IsLive > 1
				  OR b.liveindicator = @IsLive)
			 AND b.ruben = 1
			 AND b.statusID IN(111, 112, 113)
	GROUP BY ag.site
	
	OPTION(RECOMPILE)
                   
    SELECT d.RowName, 
           d.MemberWinLoss AS MemberWinLoss, 
           d.SMAWinLoss AS SMAWinLoss, 
           -d.ExtraPT AS ExtraPT, 
           d.Commission AS Commission, 
           d.RealIncome AS RealIncome, 
           d.RealTurnover AS RealTurnover
    FROM #Data AS d
    ORDER BY RowName
	    
	DROP TABLE #Agent
	DROP TABLE #Data
    DROP TABLE #DepositSuper
GO