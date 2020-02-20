/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Automail_WeeklyVoidTickets]
	@FromDate    DATE,
	@ToDate      DATE
AS
/*
    Created	: 20200220@Cherry
	Task	: Licensee - Weekly Void Tickets Report (#128875, #128591)
	DB		: DBACC/bodb02
	
	Revision:		

	Param's Explanation:
*/ 
BEGIN
	SET NOCOUNT ON;

	SELECT si.site as LicenseeName,
			count(z.transid) as TotalVoidTickets 
			,sum(z.stake * e.EUR) as TurnoverEUR
			,sum(z.stake * e.CNY) as TurnoverRMB  
	FROM  dbo.zzzbettrans z   WITH (NOLOCK)
		INNER JOIN dbo.vw_Customer s WITH (NOLOCK) ON s.custid = z.CustID
		INNER JOIN dbo.vw_Customer s1 WITH (NOLOCK) ON s.recommend = s1.CustID
		INNER JOIN dbo.site si WITH (NOLOCK) ON si.site = s1.site
		INNER JOIN ExchangeDailyOanda e with (nolock) on e.ExchangeId = s.currency and e.ExchangeDate = z.winlostdate
	WHERE
		 si.isDeposit = 1 	
		 and z.winlostdate >= @FromDate and  z.winlostdate <= @ToDate 
	GROUP BY si.site

END	