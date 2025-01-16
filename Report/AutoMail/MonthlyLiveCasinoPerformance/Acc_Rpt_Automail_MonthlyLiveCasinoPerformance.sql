/*<info serverAlias="DBACC-bodb02" executers="wsv_nap,dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

CREATE PROCEDURE [dbo].[Acc_Rpt_Automail_MonthlyLiveCasinoPerformance]
	@FromDate    DATE,
	@ToDate      DATE
AS
/*
    Created	: 20250116
	Task	: Monthly Casino Performance (#128091)
	DB		: DBACC/bodb02
	
	Revision:		
		20250116@Jaden: Initial (convert from script adhoc #128091 to SP)


	Param's Explanation:
*/ 
BEGIN
    CREATE table #BU (BalanceUpDay date, MovebetsDay date)
    insert into #bu(BalanceUpDay, MovebetsDay)
    exec bodb02.dbo.Age_SelBalanceUpDay

    declare @BalanceUpDay date,@MovebetsDay date

    select @BalanceUpDay=(select BalanceUpDay from #BU)
    select @MovebetsDay=(select MovebetsDay from #BU)
    
    CREATE TABLE #Data (   srecommend INT, productID INT, bettype INT, CustId INT,  
            BetCount INT, CurrencyId INT, Currency NVARCHAR(50),   
            TotalBets DECIMAL(19,4), TotalBetsBase DECIMAL(19,4),   
            TotalWins DECIMAL(19,4), TotalWinsBase DECIMAL(19,4),   
            TotalRefund DECIMAL(19,4), TotalRefundBase DECIMAL(19,4),   
            CompanyTurnover DECIMAL(19,4), CompanyTurnoverBase DECIMAL(19,4),  
            RealTurnover DECIMAL(19,4), RealTurnoverBase DECIMAL(19,4),  
            CompanyGrossIncome DECIMAL(19,4), CompanyGrossIncomeBase DECIMAL(19,4),  
            CompanyComm DECIMAL(19,4),  CompanyCommBase DECIMAL(19,4),  
            ExtraPT DECIMAL(19,8), ExtraPTBase DECIMAL(19,8) ,tableCode NVARCHAR(50), winlostdate date
            )  
        

    ----------------------------------------------------------------------------------------------------------------
        INSERT INTO #Data (    srecommend,productID, bettype, CustId,  
                BetCount, CurrencyId ,   
                TotalBets, TotalBetsBase,   
                TotalWins, TotalWinsBase,   
                TotalRefund, TotalRefundBase,  
                CompanyTurnover, CompanyTurnoverBase,    
                RealTurnover, RealTurnoverBase,    
                CompanyGrossIncome, CompanyGrossIncomeBase,   
                CompanyComm, CompanyCommBase,  
                ExtraPT, ExtraPTBase       ,tableCode ,winlostdate
                )  
        
        SELECT  srecommend, productID,b.gameID,  
        CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,  
        
        COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency,   
        
        SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,  
        SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,  
        
        SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,  
        SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,  
        
        SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,  
        SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,  
        
        SUM(CASE WHEN b.statusID IN (103) THEN 0   
            WHEN b.tpositiontaking = 1 THEN 0  
            ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,   
        SUM((CASE WHEN b.statusID IN (103) THEN 0   
            WHEN b.tpositiontaking = 1 THEN 0  
            ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,   
            
        SUM(CASE WHEN b.statusID IN (103) THEN 0   
            WHEN b.tpositiontaking = 1 THEN 0  
            ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) AS RealTurnover,   
        SUM((CASE WHEN b.statusID IN (103) THEN 0   
            WHEN b.tpositiontaking = 1 THEN 0  
            ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) * actualrate) AS RealTurnoverBase,    
                
        - SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,  
        - SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,  
        
        - SUM(scomm) AS CompanyComm,  
        - SUM(scomm *actualrate) AS CompanyCommBase,  
            
        - SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0  
            ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,  
        - SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0  
            ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase  
        ,case when CHARINDEX('tableCode=', transdesc)=0 or transdesc is null then ''
        else
        SUBSTRING(
            transdesc, 
            CHARINDEX('tableCode=', transdesc) + LEN('tableCode='), 
            CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc) + LEN('tableCode=')) - (CHARINDEX('tableCode=', transdesc) + LEN('tableCode='))
        ) end AS tablecode
        ,winlostdate
        FROM  dbo.BettransLC b WITH (NOLOCK)  
        WHERE
        b.WinlostDate>@MovebetsDay and  b.WinlostDate<=@todate
        AND (b.productID in (228,159,138,170,144) or b.gameID=8211)
        and currency<>20
        AND b.statusID IN (111, 112, 113, 103)   
        GROUP BY  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.gameID ,productID
        ,case when CHARINDEX('tableCode=', transdesc)=0 or transdesc is null then ''
        else
        SUBSTRING(
            transdesc, 
            CHARINDEX('tableCode=', transdesc) + LEN('tableCode='), 
            CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc) + LEN('tableCode=')) - (CHARINDEX('tableCode=', transdesc) + LEN('tableCode='))
        ) end
        ,winlostdate
    -------------------------------------------------------------------------------------------------------------------------------------------------------
        INSERT INTO #Data (    srecommend, productID,bettype, CustId,  
                BetCount, CurrencyId ,   
                TotalBets, TotalBetsBase,   
                TotalWins, TotalWinsBase,   
                TotalRefund, TotalRefundBase,  
                CompanyTurnover, CompanyTurnoverBase,    
                RealTurnover, RealTurnoverBase,    
                CompanyGrossIncome, CompanyGrossIncomeBase,   
                CompanyComm, CompanyCommBase,  
                ExtraPT, ExtraPTBase       ,tableCode ,winlostdate
                )  
        
        SELECT  srecommend, productID,b.gameID,  
        CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,  
        
        COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency,   
        
        SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,  
        SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,  
        
        SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,  
        SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,  
        
        SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,  
        SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,  
        
        SUM(CASE WHEN b.statusID IN (103) THEN 0   
            WHEN b.tpositiontaking = 1 THEN 0  
            ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,   
        SUM((CASE WHEN b.statusID IN (103) THEN 0   
            WHEN b.tpositiontaking = 1 THEN 0  
            ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,   
            
        SUM(CASE WHEN b.statusID IN (103) THEN 0   
            WHEN b.tpositiontaking = 1 THEN 0  
            ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) AS RealTurnover,   
        SUM((CASE WHEN b.statusID IN (103) THEN 0   
            WHEN b.tpositiontaking = 1 THEN 0  
            ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) * actualrate) AS RealTurnoverBase,    
                
        - SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,  
        - SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,  
        
        - SUM(scomm) AS CompanyComm,  
        - SUM(scomm *actualrate) AS CompanyCommBase,  
            
        - SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0  
            ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,  
        - SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0  
            ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase  
        ,case when CHARINDEX('tableCode=', transdesc)=0 or transdesc is null then ''
        else
        SUBSTRING(
            transdesc, 
            CHARINDEX('tableCode=', transdesc) + LEN('tableCode='), 
            CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc) + LEN('tableCode=')) - (CHARINDEX('tableCode=', transdesc) + LEN('tableCode='))
        ) end  AS tablecode
        ,winlostdate
        FROM  dbo.BettransLC14 b WITH (NOLOCK)  
        WHERE
        winlostdate BETWEEN @BalanceUpDay and @ToDate
        AND (b.productID in (228,159,138,170,144) or b.gameID=8211)
        AND b.statusID IN (111, 112, 113, 103)   
        and currency<>20
        GROUP BY  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.gameID  ,productID
        ,case when CHARINDEX('tableCode=', transdesc)=0 or transdesc is null then ''
        else
        SUBSTRING(
            transdesc, 
            CHARINDEX('tableCode=', transdesc) + LEN('tableCode='), 
            CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc) + LEN('tableCode=')) - (CHARINDEX('tableCode=', transdesc) + LEN('tableCode='))
        ) end
        ,winlostdate
    ----------------------------------------------------------------------------------------------------------------------------------


    WHILE @FromDate < @BalanceUpDay
    BEGIN

        INSERT INTO #Data (    srecommend, productID,bettype, CustId,  
                BetCount, CurrencyId ,   
                TotalBets, TotalBetsBase,   
                TotalWins, TotalWinsBase,   
                TotalRefund, TotalRefundBase,  
                CompanyTurnover, CompanyTurnoverBase,    
                RealTurnover, RealTurnoverBase,    
                CompanyGrossIncome, CompanyGrossIncomeBase,   
                CompanyComm, CompanyCommBase,  
                ExtraPT, ExtraPTBase       ,tableCode ,winlostdate
                )  
        
        SELECT  srecommend, productID,b.gameID,  
        CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END AS CustID,  
        
        COUNT(CASE WHEN StatusID IN (111,112,113) THEN b.TransId ELSE NULL END) AS BetCount, b.Currency,   
        
        SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) AS TotalBets,  
        SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE actual_stake END) * actualrate)  AS TotalBetsBase,  
        
        SUM(CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) AS TotalWins,  
        SUM((CASE WHEN b.statusID IN (103) THEN 0 ELSE winlost END) * actualrate) AS TotalWinsBase,  
        
        SUM(CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END) AS TotalRefund,  
        SUM((CASE WHEN b.statusID IN (103) THEN actual_stake ELSE 0 END)  * actualrate) AS TotalRefundBase,  
        
        SUM(CASE WHEN b.statusID IN (103) THEN 0   
            WHEN b.tpositiontaking = 1 THEN 0  
            ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) AS CompanyTurnover,   
        SUM((CASE WHEN b.statusID IN (103) THEN 0   
            WHEN b.tpositiontaking = 1 THEN 0  
            ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.stake END) * actualrate) AS CompanyTurnoverBase,   
            
        SUM(CASE WHEN b.statusID IN (103) THEN 0   
            WHEN b.tpositiontaking = 1 THEN 0  
            ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) AS RealTurnover,   
        SUM((CASE WHEN b.statusID IN (103) THEN 0   
            WHEN b.tpositiontaking = 1 THEN 0  
            ELSE (1 - b.tpositiontaking -  CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) * b.NetStake END) * actualrate) AS RealTurnoverBase,    
                
        - SUM(winlost - actual_stake + awinlost + mwinlost + swinlost) AS CompanyGrossIncome,  
        - SUM((winlost - actual_stake + awinlost + mwinlost + swinlost)* actualrate) AS CompanyGrossIncomeBase,  
        
        - SUM(scomm) AS CompanyComm,  
        - SUM(scomm *actualrate) AS CompanyCommBase,  
            
        - SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0  
            ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8))) ExtraPT,  
        - SUM((winlost - actual_stake + CASE WHEN tpositiontaking = 1 THEN 0  
            ELSE scomm / (1 - tpositiontaking) END) * CAST(ISNULL(b.epositiontaking, 0) AS DECIMAL(9,8)) * actualrate) ExtraPTBase  
        ,case when CHARINDEX('tableCode=', transdesc)=0 or transdesc is null then ''
        else
        SUBSTRING(
            transdesc, 
            CHARINDEX('tableCode=', transdesc) + LEN('tableCode='), 
            CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc) + LEN('tableCode=')) - (CHARINDEX('tableCode=', transdesc) + LEN('tableCode='))
        ) end  AS tablecode
        ,winlostdate
        FROM  DB061.bodb_archive.dbo.BettransLC_bk b WITH (NOLOCK)  
        WHERE
        b.WinlostDate = @FromDate
        AND (b.productID in (228,159,138,170,144) or b.gameID=8211)
        AND b.statusID IN (111, 112, 113, 103)   
        and currency<>20
        GROUP BY  b.Currency, CASE WHEN b.StatusID IN (111,112,113) THEN b.CustID ELSE NULL END, srecommend, b.gameID  ,productID
        ,case when CHARINDEX('tableCode=', transdesc)=0 or transdesc is null then ''
        else
        SUBSTRING(
            transdesc, 
            CHARINDEX('tableCode=', transdesc) + LEN('tableCode='), 
            CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc) + LEN('tableCode=')) - (CHARINDEX('tableCode=', transdesc) + LEN('tableCode='))
        ) end
        ,winlostdate

        Select @FromDate = dateadd(DAY,1,@FromDate)

    END 
        -----------------------------
    --WE Live Casino
    SELECT  s.SportName [Product],winlostdate,re.resource_en [tableCode],--b.tableCode,
        -- COUNT(DISTINCT b.CustId) AS NoOfPlayers,   
        SUM(b.BetCount) AS BetCount ,  
        'RM' AS Currency,  
        SUM (b.TotalBetsBase) AS TotalBets,   
        SUM (b.TotalBetsBase-b.TotalWinsBase) AS [Game Income],  
        -- SUM (b.TotalRefundBase) AS TotalRefund,  
    --  SUM (b.CompanyTurnoverBase) AS HouseTurnover,  
        SUM (b.RealTurnoverBase) AS RealTurnover,  
        SUM (b.CompanyGrossIncomeBase) AS HouseGrossIncome,  
        SUM (b.CompanyCommBase) AS HouseComm,  
        SUM (b.ExtraPTBase) ExtraPT  ,
        SUM( b.CompanyCommBase-b.ExtraPTBase+b.CompanyGrossIncomeBase) NetIncome
    FROM #Data b   
    left join  Refresource   re with (nolock) on re.refid='WE_BT' and b.tableCode=re.Resourceid 
    left join sports s with (nolock) on s.SportType=b.productID
    where productID=228
    group by winlostdate,resource_en,s.SportName--,b.tableCode
    order by winlostdate,resource_en

    --FGG
    SELECT  s.SportName [Product],winlostdate,re.resource_en [tableCode],--tableCode,
        -- COUNT(DISTINCT b.CustId) AS NoOfPlayers,   
        SUM(b.BetCount) AS BetCount ,  
        'RM' AS Currency,  
        SUM (b.TotalBetsBase) AS TotalBets,   
        SUM (b.TotalBetsBase-b.TotalWinsBase) AS [Game Income],  
        -- SUM (b.TotalRefundBase) AS TotalRefund,  
    --  SUM (b.CompanyTurnoverBase) AS HouseTurnover,  
        SUM (b.RealTurnoverBase) AS RealTurnover,  
        SUM (b.CompanyGrossIncomeBase) AS HouseGrossIncome,  
        SUM (b.CompanyCommBase) AS HouseComm,  
        SUM (b.ExtraPTBase) ExtraPT  ,
        SUM( b.CompanyCommBase-b.ExtraPTBase+b.CompanyGrossIncomeBase) NetIncome
    FROM #Data b   
    left join  Refresource  re with (nolock) on re.refid='FGG_GN' and b.tableCode=re.Resourceid 
    left join sports s with (nolock) on s.SportType=b.productID
    where  b.bettype=8211 
    group by winlostdate,resource_en,s.SportName--,tableCode
    order by winlostdate,resource_en

    --Yeebet
    SELECT  s.SportName [Product],winlostdate,tableCode,
        -- COUNT(DISTINCT b.CustId) AS NoOfPlayers,   
        SUM(b.BetCount) AS BetCount ,  
        'RM' AS Currency,  
        SUM (b.TotalBetsBase) AS TotalBets,   
        SUM (b.TotalBetsBase-b.TotalWinsBase) AS [Game Income],  
        -- SUM (b.TotalRefundBase) AS TotalRefund,  
    --  SUM (b.CompanyTurnoverBase) AS HouseTurnover,  
        SUM (b.RealTurnoverBase) AS RealTurnover,  
        SUM (b.CompanyGrossIncomeBase) AS HouseGrossIncome,  
        SUM (b.CompanyCommBase) AS HouseComm,  
        SUM (b.ExtraPTBase) ExtraPT  ,
        SUM( b.CompanyCommBase-b.ExtraPTBase+b.CompanyGrossIncomeBase) NetIncome
    FROM #Data b   
        left join sports s with (nolock) on s.SportType=b.productID
    where productID=159 
    group by winlostdate,tableCode,s.SportName
    order by winlostdate,tableCode

    -- ON Casino
    SELECT  s.SportName [Product],winlostdate,re.resource_en [tableCode],--tableCode,
        -- COUNT(DISTINCT b.CustId) AS NoOfPlayers,   
        SUM(b.BetCount) AS BetCount ,  
        'RM' AS Currency,  
        SUM (b.TotalBetsBase) AS TotalBets,   
        SUM (b.TotalBetsBase-b.TotalWinsBase) AS [Game Income],   
        -- SUM (b.TotalRefundBase) AS TotalRefund,  
    --  SUM (b.CompanyTurnoverBase) AS HouseTurnover,  
        SUM (b.RealTurnoverBase) AS RealTurnover,  
        SUM (b.CompanyGrossIncomeBase) AS HouseGrossIncome,  
        SUM (b.CompanyCommBase) AS HouseComm,  
        SUM (b.ExtraPTBase) ExtraPT  ,
        SUM( b.CompanyCommBase-b.ExtraPTBase+b.CompanyGrossIncomeBase) NetIncome
    FROM #Data b   
    left join  Refresource  re with (nolock) on re.refid='ON_BT' and b.tableCode=re.Resourceid 
    left join sports s with (nolock) on s.SportType=b.productID
    where  b.productID=138 
    group by winlostdate,resource_en,s.SportName--,tableCode
    order by winlostdate,resource_en

        -- PP Live Casino
    SELECT  s.SportName [Product],winlostdate,bt.typenamee [Game Type],--tableCode,
        -- COUNT(DISTINCT b.CustId) AS NoOfPlayers,   
        SUM(b.BetCount) AS BetCount ,  
        'RM' AS Currency,  
        SUM (b.TotalBetsBase) AS TotalBets,   
        SUM (b.TotalBetsBase-b.TotalWinsBase) AS [Game Income],  
        -- SUM (b.TotalRefundBase) AS TotalRefund,  
    --  SUM (b.CompanyTurnoverBase) AS HouseTurnover,  
        SUM (b.RealTurnoverBase) AS RealTurnover,  
        SUM (b.CompanyGrossIncomeBase) AS HouseGrossIncome,  
        SUM (b.CompanyCommBase) AS HouseComm,  
        SUM (b.ExtraPTBase) ExtraPT  ,
        SUM( b.CompanyCommBase-b.ExtraPTBase+b.CompanyGrossIncomeBase) NetIncome
    FROM #Data b   
    left join  bettype bt with (nolock) on bt.typeid=b.bettype
    left join sports s with (nolock) on s.SportType=b.productID
    where  b.productID=170
    group by winlostdate,bt.typenamee,s.SportName--,tableCode
    order by winlostdate,bt.typenamee

        -- GPI Live Casino
    SELECT  s.SportName [Product],winlostdate,bt.typenamee [Game Type],--tableCode,
        -- COUNT(DISTINCT b.CustId) AS NoOfPlayers,   
        SUM(b.BetCount) AS BetCount ,  
        'RM' AS Currency,  
        SUM (b.TotalBetsBase) AS TotalBets,   
        SUM (b.TotalBetsBase-b.TotalWinsBase) AS [Game Income],  
        -- SUM (b.TotalRefundBase) AS TotalRefund,  
    --  SUM (b.CompanyTurnoverBase) AS HouseTurnover,  
        SUM (b.RealTurnoverBase) AS RealTurnover,  
        SUM (b.CompanyGrossIncomeBase) AS HouseGrossIncome,  
        SUM (b.CompanyCommBase) AS HouseComm,  
        SUM (b.ExtraPTBase) ExtraPT  ,
        SUM( b.CompanyCommBase-b.ExtraPTBase+b.CompanyGrossIncomeBase) NetIncome
    FROM #Data b   
    left join  bettype bt with (nolock) on bt.typeid=b.bettype
    left join sports s with (nolock) on s.SportType=b.productID
    where  b.productID=144 
    group by winlostdate,bt.typenamee,s.SportName--,tableCode
    order by winlostdate,bt.typenamee
 END