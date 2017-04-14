ALTER Procedure [dbo].[Task_CalcList_Match]
/*
	Name: 
	Creator: 
	Created: 20090729
	Task: call to update summary for winlost report
	This SP is unused
*/
AS
	Declare @match TABLE (MatchID int)
	INSERT INTO @match
	SELECT MatchID
	FROM dbo.CalcList_Match with (nolock)
	
	Declare @MatchID int, 
			@cnt int
StartLoop:
	SELECT TOP 1 @MatchID = MatchID FROM @match
		
	SELECT @cnt = @@ROWCOUNT
	IF @cnt = 0 GOTO EndLoop

	-- Check If got ticket on this match
	IF (EXISTS(SELECT TOP 1 matchid FROM bettrans with (nolock) WHERE matchid = @MatchID))
	BEGIN
		--call SP to sum data
		EXEC dbo.Task_rptWinLost_Summary @MatchID
	END
	
	delete dbo.CalcList_Match where MatchID = @MatchID
	
	DELETE FROM @match WHERE matchid = @MatchID

	GOTO StartLoop
EndLoop:

GO
GRANT VIEW DEFINITION ON [dbo].[Task_CalcList_Match] TO [vnteam]