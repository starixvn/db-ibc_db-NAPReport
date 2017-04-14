ALTER PROCEDURE dbo.Acc_Rpt_WinlostP2P
	@FromDate SMALLDATETIME,
	@ToDate SMALLDATETIME,
	@MoveBetsDay SMALLDATETIME
	
/*	Creator: 20110829@TOM
	Task: Report 2A for P2P
	DB: DB06.bodb02
	Original: 

	Revisions:
		- 20120418@Johnson: correct comm of company is the net comm
		- 20120608@Elodie: Change the gross commission for P2P
		
	Explanation's Param:
	
	
*/
AS
SET NOCOUNT ON

Create TABLE #tblReport (
		Winlossdate SMALLDATETIME ,
		CurrencyName NVARCHAR(50) , 
		currency	TINYINT ,
		Winloss MONEY ,
		CommPlayer MONEY ,
		CommAgent MONEY ,
		CommMaster MONEY ,
		CommSuper MONEY ,
		CommCompany MONEY ,
		CommGross MONEY ,
		CommGrossVSRM MONEY ,
		CommCompanyVSRM MONEY
		)
CREATE CLUSTERED INDEX IX_1 on #tblReport (Winlossdate, CurrencyName, currency)

IF (@Todate > @MoveBetsDay) 
	BEGIN
		INSERT INTO #tblReport (Winlossdate , CurrencyName , currency ,Winloss , 
				CommPlayer , CommAgent , CommMaster , CommSuper , CommCompany , 
				CommGross , CommGrossVSRM , CommCompanyVSRM )--, actualrate )
		SELECT  winlostdate, CurrencyName , currency , SUM (winlost -actual_stake ) AS [Win/loss], 
				SUM (playercomm ) AS [comm-Player] ,
				SUM (comm - playercomm ) AS [comm-Agent] , 
				SUM (acomm - comm ) AS [comm-Master] , 
				SUM (scomm - acomm ) AS [comm-Super], 
				SUM (odds - scomm) AS [Comm_Company],
				SUM (oddsspread) AS grosscomm , 
				SUM (oddsspread * actualrate) AS GrossComm2RM , 
				SUM ((odds - scomm) * actualrate) AS Comm_Company2RM --, 
		  FROM  dbo.bettrans	 (NOLOCK)
			WHERE bettype = 1000
				AND matchid = 1000
				AND winlostdate BETWEEN @fromdate AND @todate
				AND ruben = 1 
				AND statusID NOT IN (101,102,103,121)
		GROUP BY winlostdate, CurrencyName , currency 
	END
IF (@Fromdate <= @MoveBetsDay)
	BEGIN
		INSERT INTO #tblReport (Winlossdate , CurrencyName , currency ,Winloss , 
				CommPlayer , CommAgent , CommMaster , CommSuper , CommCompany , 
				CommGross , CommGrossVSRM , CommCompanyVSRM )
		SELECT  winlostdate, CurrencyName , currency , SUM (winlost -actual_stake ) AS [Win/loss], 
				SUM (playercomm ) AS [comm-Player] ,
				SUM (comm - playercomm ) AS [comm-Agent] , 
				SUM (acomm - comm ) AS [comm-Master] , 
				SUM (scomm - acomm ) AS [comm-Super], 
				SUM (odds - scomm) AS [Comm_Company],
				SUM (oddsspread ) AS grosscomm , 
				SUM (oddsspread * actualrate) AS GrossComm2RM , 
				SUM ((odds - scomm) * actualrate) AS Comm_Company2RM
		  FROM  dbo.bettrans14	 (NOLOCK)
			WHERE bettype = 1000
				AND matchid = 1000
				AND winlostdate BETWEEN @fromdate AND @todate
				AND ruben = 1 
				AND statusID NOT IN (101 , 102 , 103, 121)	
		GROUP BY winlostdate, CurrencyName , currency
	END

SELECT Winlossdate , CurrencyName , currency ,
	SUM(Winloss ) Winloss , SUM(CommPlayer) CommPlayer  , 
	SUM(CommAgent ) CommAgent , SUM(CommMaster) CommMaster , 
	SUM(CommSuper) CommSuper , SUM(CommCompany) CommCompany , 
	SUM (CommGross) CommGross , SUM(CommGrossVSRM) CommGrossVSRM , 
	SUM(CommCompanyVSRM) CommCompanyVSRM
FROM #tblReport
GROUP BY Winlossdate , CurrencyName , currency 


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostP2P] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostP2P] TO [vnteam] 