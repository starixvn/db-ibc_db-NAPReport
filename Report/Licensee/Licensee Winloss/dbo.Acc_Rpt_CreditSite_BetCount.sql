
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.Acc_Rpt_CreditSite_BetCount    Script Date: 10/11/2016 1:00:55 PM ******/
/****** Object:  Stored Procedure dbo.Acc_Rpt_CreditSite_BetCount    Script Date: 9/27/2016 4:21:10 PM ******/

CREATE PROCEDURE [dbo].[Acc_Rpt_CreditSite_BetCount]
    @datestart SMALLDATETIME ,
    @dateend   SMALLDATETIME
AS 

/*	Creator: Don
	Date: 2011-04-06
	Task: Get total of bet count
	DB: DBLIC.bodb_licensee
	Original :GET_Acc_CreditSite_BetCount
			   20130919@Jim: clone SP from DBDW2.bodb_dwrs
			   20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
	Revisions:
	    
		
*/
SET NOCOUNT ON

SELECT
	l.labelName AS site,
	SUM(betcount) AS betcount
FROM
	bodb_licenseereport.dbo.rpt_betting b WITH (NOLOCK)
	INNER JOIN dbo.Labels l WITH ( NOLOCK ) ON b.siteid = l.labelid
		
WHERE  rptDate BETWEEN @datestart AND @dateend
	AND [status] NOT IN (-1,103) -- Refund
	AND isnull(b.customercategory,-1) NOT IN ( 27,28 )-- added BARM ,8RM
	AND currencyid <> 20
	AND (
	bettype < 31 
	OR (bettype BETWEEN 121 AND 999)
	OR (bettype BETWEEN 1301 AND 1334)
	)
GROUP BY l.labelName 

SET NOCOUNT OFF
GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CreditSite_BetCount] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_CreditSite_BetCount] TO [bodbLicenseeNet]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_CreditSite_BetCount] TO [bodbAdminNet]
GO 
