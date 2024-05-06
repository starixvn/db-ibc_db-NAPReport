/*<info serverAlias="DBACC-bodb02"></info>*/

EXEC msdb.dbo.sp_add_job @job_name = 'AutomailBalanceBreakdownJob';
EXEC msdb.dbo.sp_add_jobstep
    @job_name = 'AutomailBalanceBreakdownJob',
    @step_name = 'Generate Data (Daily)',
    @command = 'EXEC bodb02.dbo.Acc_Rpt_Automail_BalanceBreakdown_Job @IsMonthly = 0',
    @subsystem = 'TSQL';
EXEC msdb.dbo.sp_add_jobstep
    @job_name = 'AutomailBalanceBreakdownJob',
    @step_name = 'Generate Data (Monthly)',
    @command = '
    DECLARE @CurrentDate DATE = GETDATE();
    IF (DAY(@CurrentDate) = 3)
    BEGIN
        EXEC bodb02.dbo.Acc_Rpt_Automail_BalanceBreakdown_Job @IsMonthly = 1
    END
    ',
    @subsystem = 'TSQL';


EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'DailyAt3am',
    @freq_type = 4, -- Daily
    @freq_interval = 1, -- Every 1 day
    @active_start_time = 030000; -- 3:00 AM
GO

EXEC msdb.dbo.sp_attach_schedule
    @job_name = N'AutomailBalanceBreakdownJob',
    @schedule_name = N'DailyAt3am';
GO