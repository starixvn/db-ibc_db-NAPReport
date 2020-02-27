/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_Universal_SportType_CN88
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @ProductId    INT
AS
/*	
    Creator: Robert
	Date: 2016-05-11
	Task: Company Winloss Report - Main SP [Redmine: #116083]
	DB: DBACC/bodb02	
		
	Revisions:
		- 20190710@Robert: 	NAP Report - Implement new report to match with CN88's need [#116083]
		- 20191212@Ned.Le:  Support to get Extra PT from Extra PT column [#125286]
	Explanation's Param:	
*/

BEGIN
    SET NOCOUNT ON;

    DECLARE @FDate    SMALLDATETIME
		, @TDate    SMALLDATETIME
		, @ProID    INT;

    SELECT @FDate = @StartDate
	    , @TDate = @EndDate
	    , @ProID = @ProductId;

    BEGIN --#SportBetType     
	   DECLARE @isTest    BIT = 0;
	   SELECT @isTest = dbo.f_CheckSPVersion
			(@@PROCID);
	   CREATE TABLE #SportBetType(
		   BetType      INT
		 , SportType    INT
		 , SportName    NVARCHAR(100));
	   INSERT INTO #SportBetType
			SELECT DISTINCT
				  t.BetType
				, t.SportType
				, d.SportName
			FROM dbo.f_SportBetTypeMatrix_Sel
				(@ProID, 0, 0, 2, '', '', @isTest) AS s
			    INNER JOIN dbo.SportBettypeMatrix AS t WITH (NOLOCK) ON t.BetType = s.BetType
															AND t.ProductId = s.ProductId
			    INNER JOIN dbo.Sports AS d WITH (NOLOCK) ON d.SportType = t.SportType
			WHERE s.SubProduct = '';
    END;

    BEGIN -- Query
	   SELECT sb.SportType AS GroupId
		   , sb.SportName AS GroupName
		   , SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss
		   , SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss
		   , -SUM(CASE
				    WHEN b.tpositiontaking = 1
				    THEN 0
				    ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
				END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS HeadlineIncome
		   , SUM(scomm * actualrate) AS Commission
		   , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
																		WHEN tpositiontaking = 1
																		THEN 0
																		ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																	 END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome
		   , SUM(CASE
				   WHEN tpositiontaking = 1
				   THEN 0
				   ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.stake * CASE
																		WHEN virtualrate > actualrate
																		THEN virtualrate
																		ELSE actualrate
																	 END
			    END) AS RealTurnover
	   FROM bettrans AS b WITH (NOLOCK)
		  INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
		  INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
	   WHERE b.winlostdate = @FDate
		    AND b.ruben = 1
		    AND b.statusID IN(111, 112, 113)
	   GROUP BY sb.SportType
			, sb.SportName
	   ORDER BY GroupName;
    END;

    DROP TABLE #SportBetType;
END;
GO