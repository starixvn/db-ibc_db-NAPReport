ALTER PROCEDURE [dbo].[Acc_HedgeUpd]
	@transid bigint,
	@odds smallmoney,
	@hdp1 smallmoney,
	@hdp2 smallmoney,
	@stake money,
	@livehomescore smallint = NULL,
	@liveawayscore smallint = NULL,
	@creator int,
	@Remark nvarchar(200),
	@ErrCode		int = 0 OUTPUT,
	@ErrMsg			nvarchar(200) = '' OUTPUT
AS
/*
Created: 
Task : Update hedge info in Betting graph report
DB: DB02.bodb02
Original:

Revisions:
    - 20091216@Daniel: Add check permission & error control
    - 20100720@Henry: Change SP Logfile to WriteLog_UserLog
    - 20101007@Henry: Change column transid from INT to BIGINT
    - 20140212@Johnson: change alias server DB03 to DBPOLICY

Param's Explanation:
• @ErrCode:
    = 0: Transaction recorded successfully.
    > 0: Specific Error.
    
• @ErrMsg: Error description.
*/
	SET NOCOUNT ON
	--Check permission
	EXEC DBPOLICY.bodb02.dbo.Acc_Con_CheckPermission @custid=@creator, @funcname='[SpecialReportBettingGraph]',@ErrCode=@ErrCode output,@ErrMsg=@ErrMsg output
	If @ErrCode <> 0
		RETURN

	UPDATE dbo.BetHedgeRecord WITH(ROWLOCK,UPDLOCK)
	SET odds = @odds,
		hdp1 = @hdp1,
		hdp2 = @hdp2,
		stake = @stake,
		livehomescore = ISNULL(@livehomescore,livehomescore),
		liveawayscore = ISNULL(@liveawayscore,liveawayscore),
		remark = @remark,
		creator = @creator
	WHERE transid=@transid
		

	Declare @LogData nvarchar(200)
	SELECT @LogData = 'Hedge Update TransID:' + CAST(@transid as nvarchar(20))
		+ ' odds:' + CAST(CAST(@odds as float) as nvarchar(20)) 
		+ ' hdp:' + CAST(@hdp1 as nvarchar(10)) + '-' + CAST(@hdp2 as nvarchar(10))
		+ ' stake:' + CAST(CAST(@stake as float) as nvarchar(20))
		+ ' live-h-a:' + CAST(@livehomescore as nvarchar(10)) + '-' + CAST(@liveawayscore as nvarchar(10))
	EXEC dbo.WriteLog_UserLog @creator, @LogData

GO
GRANT EXECUTE ON [dbo].[Acc_HedgeUpd] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_HedgeUpd] TO [vnteam]