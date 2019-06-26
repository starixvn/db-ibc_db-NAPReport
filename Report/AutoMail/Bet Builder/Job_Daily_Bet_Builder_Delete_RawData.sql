/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Job_Daily_Bet_Builder_Delete_RawData
AS
/*
	Creator: Robert
	Date: 2019-05-27
	DB: DBACC.bodb02
	Task: Bet Builder - Daily Automail report to 3rd
	Revisions:		
		- 20190527@Robert: Bet Builder - Daily Automail report to 3rd [#114248]

	Param's Explanation:	   
*/

BEGIN
    SET NOCOUNT ON;

    DECLARE @WinlostDate SMALLDATETIME= CONVERT(VARCHAR(10), DATEADD(MONTH, -3, GETDATE()), 110);

    DELETE b
    FROM bodb_Report.dbo.BetBuilder_BetHistoryAutomail b
    WHERE b.WinlostDate <= @WinlostDate;
END;