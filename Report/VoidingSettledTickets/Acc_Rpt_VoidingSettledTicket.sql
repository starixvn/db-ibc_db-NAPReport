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
    CREATE TABLE #Result 
	(	ProductGroup VARCHAR(50),
		HouseIncomeBeforeExtraPT MONEY,
		HouseIncomeAfterExtraPT MONEY	
	)
	INSERT INTO #Result VALUES('SPL', 2000, 3000)
	INSERT INTO #Result VALUES('SPNL', -2000, -3000)
	INSERT INTO #Result VALUES('Parlay', -2500, -3000)
	INSERT INTO #Result VALUES('Outright', -2000, -2500)
	INSERT INTO #Result VALUES('Bet Builder', 2500, 3000)
	INSERT INTO #Result VALUES('Metric Gaming - Super Live', 2000, 3000)
	INSERT INTO #Result VALUES('Muay Thai', 5000, 8000)
	INSERT INTO #Result VALUES('Cash Out', 4000, 6000)
	INSERT INTO #Result VALUES('CN88 SPL', -2000, -3000)
	INSERT INTO #Result VALUES('CN88 SPNL', -2500, -3000)
	INSERT INTO #Result VALUES('CN88 Parlay', 1000, 2000)
	INSERT INTO #Result VALUES('CN88 Outright', -2000, -3000)
	
	SELECT *
	FROM #Result
	
END

GO
