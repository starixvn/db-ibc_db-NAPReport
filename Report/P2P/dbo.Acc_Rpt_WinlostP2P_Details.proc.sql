ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostP2P_Details]	
	@currency	TINYINT,
	@winlostdate SMALLDATETIME

/*	Creator: 20110829@TOM
	Task: Report 2A for P2P
	DB: DB06.bodb02
	Original: 

	Revisions:
		- 20120418@Johnson: Correct commission of company is the net comm
		- 20120608@Elodie: Change the gross commission for P2P
	Explanation's Param:


*/
AS
SET NOCOUNT ON

Create TABLE #tblReport (
		CustID INT,
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
CREATE CLUSTERED INDEX IX_1 on #tblReport (CustID)

INSERT INTO #tblReport (CustID , Winloss , 
		CommPlayer , CommAgent , CommMaster , CommSuper , CommCompany , 
		CommGross , CommGrossVSRM , CommCompanyVSRM )
SELECT  cust.SRECOMMEND	 ,
		SUM (bet.winlost -bet.actual_stake ) AS [Winloss], 
		SUM (bet.playercomm ) AS [CommPlayer] ,
		SUM (bet.comm - bet.playercomm ) AS [CommAgent] , 
		SUM (bet.acomm - bet.comm ) AS [CommMaster] , 
		SUM (bet.scomm - bet.acomm ) AS [CommSuper], 
		SUM (bet.odds - bet.scomm ) AS [CommCompany],
		SUM (bet.oddsspread ) AS CommGross , 
		SUM (bet.oddsspread * bet.actualrate) AS CommGrossVSRM , 
		SUM ((bet.odds - bet.scomm)* bet.actualrate) AS CommCompanyVSRM				
  FROM  dbo.bettrans	bet (NOLOCK)
	INNER JOIN dbo.custInfo cust	 (NOLOCK)
		ON bet.custid = cust.custid 
	WHERE bet.bettype = 1000
		AND bet.matchid = 1000
		AND bet.winlostdate = @winlostdate
		AND bet.ruben = 1 
		AND bet.currency = @currency
		AND bet.statusID NOT IN (101,102,103,121)		
GROUP BY cust.SRECOMMEND

SELECT	tbl.CustID , cust.Username ,
		@winlostdate Winlossdate ,
		exc.currency CurrencyName , 
		cust.currency,
		tbl.Winloss ,
		tbl.CommPlayer ,
		tbl.CommAgent ,
		tbl.CommMaster ,
		tbl.CommSuper ,
		tbl.CommCompany ,
		tbl.CommGross ,
		tbl.CommGrossVSRM ,
		tbl.CommCompanyVSRM
FROM #tblReport tbl
  INNER JOIN bodb02 . dbo . custInfo cust	 (NOLOCK)
	ON	tbl.CustID = cust.CustID 
  INNER JOIN bodb02 . dbo .EXCHANGE exc (Nolock)
	ON @currency = exc.Exchangeid

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostP2P_Details] TO [bodbAdminNet]
GO
GRANT VIEW definition ON [dbo].[Acc_Rpt_WinlostP2P_Details] TO [vnteam] 