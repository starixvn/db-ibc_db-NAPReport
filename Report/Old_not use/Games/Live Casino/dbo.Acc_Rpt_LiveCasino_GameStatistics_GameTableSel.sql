ALTER  PROCEDURE [dbo].Acc_Rpt_LiveCasino_GameStatistics_GameTableSel
    @GameTypeID int = 0,
	@ExcludeTest bit = 0
AS
SET NOCOUNT ON
/*
Created by: Daniel
Date: 2012-02-17
Task : Retrieve all game tables for Live Casino
DB: DB06.bodb02
Original:

Revisions:
	-20120910@Jim: change to use leaguenametc column for support live casino
	-20130910@Dom: Update Istest condition
*/
SET NOCOUNT ON



if @GameTypeID = 0
BEGIN
    SELECT	leagueid GameTableID, leaguename GameTable
    FROM	league WITH (NOLOCK)
    WHERE	sporttype = 162
		AND (@ExcludeTest = 0 OR isTest = 0)
    ORDER BY leagueid ASC
END
ELSE
BEGIN
    
    SELECT	leagueid GameTableID, leaguename GameTable
    FROM	league WITH (NOLOCK)
    WHERE	sporttype = 162
      AND leaguenametc =convert(char,@GameTypeID )
	  AND (@ExcludeTest = 0 OR isTest = 0)
    ORDER BY leagueid ASC
END

GO
GRANT EXECUTE ON [dbo].Acc_Rpt_LiveCasino_GameStatistics_GameTableSel TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].Acc_Rpt_LiveCasino_GameStatistics_GameTableSel TO [vnteam]

