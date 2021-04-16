USE [bodb_report] 
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_DuplicatedTicketsCheckCashOut]
	@sTransID VARCHAR(MAX)
	,@isDuplicated BIT = 0 OUTPUT
AS
/*
Created: 20180116@Tom
Task :	Check Duplicated ticket report of Cash Out Product
DB:		DBRPT/bodb_report
Original: 

Revisions:
	- 20210416@Ned.Le: NAP Report - Duplicate Tickets - Exclude refund tickets (#153616)

Param's Explanation:

*/
BEGIN
	SET NOCOUNT ON;

	DECLARE @Original_Stake MONEY;
	DECLARE @Sell_Stake MONEY;
	DECLARE @RefNo BIGINT;

	DECLARE @tbl_transid TABLE(transid BIGINT);

	INSERT INTO @tbl_transid(transid)
	SELECT f.val FROM bodb02.[dbo].[strSplit] (@sTransID,',') f;

	SELECT @RefNo = bt.refno 
	FROM bodb02.dbo.bettrans bt WITH(NOLOCK)
	WHERE EXISTS(SELECT TOP 1 1 FROM @tbl_transid tmp WHERE bt.transid = tmp.transid);

	SELECT @Original_Stake = ISNULL(CAST(('<xml>'+bt.ExtraInfo+'</xml>') AS XML).value('data(/xml/p25/@s)[1]', 'MONEY'), 0)
		,@Sell_Stake = bt.stake
	FROM bodb02.dbo.bettrans bt WITH(NOLOCK)
	WHERE bt.transid = @RefNo;

	SELECT @Sell_Stake = SUM(bt.stake) + @Sell_Stake	
	FROM bodb02.dbo.bettrans bt WITH(NOLOCK)
	WHERE bt.refno = @RefNo
	AND bt.statusID NOT IN(101,102,103);

	IF (@Sell_Stake <> @Original_Stake)
		SET @isDuplicated = 1
	ELSE 
		SET @isDuplicated = 0;
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DuplicatedTicketsCheckCashOut] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DuplicatedTicketsCheckCashOut] TO [vnteam]
GO