/*<info serverAlias="DBBAH-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE dbo.Acc_Rpt_VoidingSettledTicket
	@WinlostDate DATE
   , @VoidTime   SMALLDATETIME
   , @MatchId    INT
AS
/*  
Created by: Cherry  
Date: 2020-10-10 
Task : Voiding Settled Tickets
DB: DBBAH.bodb02  
Original SP:   
Revisions:  
	20201010@Cherry : Voiding Settled Tickets (#142454)		

*/

BEGIN
    SET NOCOUNT ON
    CREATE TABLE #VoidTrans 
		(TransID BIGINT, 
		CustID INT, 
		VoidDate DATETIME, 
		Bettype INT, 
		Matchid INT, 
		Recommend INT,
		liveindicator BIT,
		ActualRate FLOAT, 
		tpositiontaking SMALLMONEY, 
		epositiontaking SMALLMONEY)
	CREATE TABLE #VoidRecord 
		(TransID BIGINT, 
		CustID INT, 
		ActionDate SMALLDATETIME)
	CREATE TABLE #SettledRecord 
		(TransID BIGINT, 
		CustID INT, 
		winlost MONEY, 
		actual_stake MONEY, 
		awinlost MONEY, 
		mwinlost MONEY, 
		swinlost MONEY, 
		scomm MONEY)
	CREATE TABLE #Result 
		(ProductGroup VARCHAR(50),	
		HouseIncomeBeforeExtraPT MONEY,	
		HouseIncomeAfterExtraPT MONEY)

	INSERT INTO #VoidTrans (TransID, CustID, VoidDate)
	SELECT z.transid, z.custid, z.transdate
	  FROM bodb02.dbo.zzzbettrans z (NOLOCK)
		inner join bodb02.dbo.bettrans b (NOLOCK) ON z.custid = b.custid AND z.transid = b.transid 
	  where z.status in ('WON','LOSE','DRAW')
		  and b.winlostdate = '20201006'
		  and z.transdate >= '20201006 00:00:00'
		  and b.currency <> 20
  
	INSERT INTO #VoidRecord (TransID, CustID, ActionDate)
	SELECT b.TransID, b.CustID, MAX(b.ActionDate)
	FROM bodb02.dbo.BalanceRecord b (NOLOCK)
	WHERE EXISTS(SELECT TOP 1 1 FROM #VoidTrans v WHERE b.TransID = v.TransID AND b.CustID = v.CustID)
	AND ActionID = 50
	GROUP BY b.TransID, b.CustID

	INSERT INTO #SettledRecord (TransID, CustID, RowID)
	SELECT b.transid, b.custid, b.RowID
	FROM bodb02.dbo.BalanceRecord b (NOLOCK)
	WHERE b.ActionDate = (SELECT MAX(c.ActionDate)
						  FROM bodb02.dbo.BalanceRecord c (NOLOCK)
						  WHERE EXISTS(SELECT TOP 1 1 FROM #VoidRecord v WHERE c.TransID = v.TransID AND c.CustID = v.CustID AND c.ActionDate < v.ActionDate))
		AND EXISTS(SELECT TOP 1 1 FROM #VoidRecord v WHERE b.TransID = v.TransID AND b.CustID = v.CustID)
    
	DROP TABLE #VoidTrans
	DROP TABLE #VoidRecord
	DROP TABLE #SettledRecord
	
	SELECT *
	FROM #Result
	
END

GO
