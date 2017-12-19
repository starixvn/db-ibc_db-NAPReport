ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostCA_Details]
	@winlostdate	datetime
AS 
	/*	Creator: Phuong Dao
		Date: 2009-05-06
		Task: Report 2A for Casino 
		DB: DBACC/bodb02
		Original: 
	
		History:
			- 20090522@PhuongDao: Add TurnOver 
			- 20100522@Henry: Change to use StatusID instead of Status in WHERE statement
			- 20120405@Hurri: Exclude bettype 72 (P2P bet ticket) in the calculation of Casino
			- 20130703@Kathy: Update matchid for RnG Casino (71) 
			- 20130717@Kathy: Apply Progressive Bonus: add bettype 72 for Casino
			- 20160127@Percy: Expand new range RNG Casino [Redmine: #49134]
		
		Explanation's Param:

	*/
	SET NOCOUNT ON

	-- Get sport bettype
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT)
	INSERT INTO @SportBettype (ProductID  , Bettype  ,EventType)
		EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode = 4, @ProductID = 6

	DELETE @SportBettype WHERE bettype = 72

	SELECT	71 bettype,
			currency,
			currencyName,
			isnull(sum(actual_stake * b.actualrate),0) Turnover,
			isnull(sum((winlost-actual_stake)*b.actualrate),0)  winlost, 
			isnull(sum((awinlost+mwinlost+swinlost)*b.actualrate),0) pos,
			isnull(sum( scomm*b.actualrate),0) comm,
			isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*b.actualrate),0) as LineTotal			
	FROM	bettransRnG b with (NOLOCK) 
	WHERE	winlostdate = @winlostdate  
			--AND ruben = 1 
			AND gameID IN (SELECT Bettype FROM @SportBettype)
			AND statusID NOT IN (101,102,121)
	GROUP BY --bettype, 
		currency, currencyName 
	ORDER BY bettype, currency


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostCA_Details] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostCA_Details] TO [VNTeam]
GO