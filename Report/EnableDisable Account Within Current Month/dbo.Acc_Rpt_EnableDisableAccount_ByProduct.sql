/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_EnableDisableAccount_ByProduct
	@ListCurrency    VARCHAR(8000) = 'all'
   , @SportType       INT
   , @ShowEnabled     BIT           = 1
   , @ShowDisabled    BIT           = 1
AS
/*  Created: Dominic 
	Date: 2014-06-02  
    Task : Total Credit Accounts Enabled/Disabled per Product
    DB: DBACC/bodb02
   
    Revisions:  
		- 20140627@Dominic: Exclude special super with username  LIKE '3rdSuper%','STEST%','%ACCSuper%'
		- 20140707@Dominic: Add Param @ShowEnabled/@ShowDisabled #18655
		- 20150609@Kos: Separate CustDB to DBCUST server (Move SP to DBACC.bodb02)
		- 20150828@Jim: support GoldDeluxe & Metric Gaming(#40262)
		- 20150828@Jim: support Colossus Bet (#42608)
		- 20151215@Percy: support Cockfighting [Redmine: #49027]
		- 20160108@Percy: Add new range bettype for Casino [Redmine: #49134]
		- 20160229@Jim: Offer Allbet [Redmine #50921]
		- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model [RedmineID: #55589]		
		- 20160916@Robert:
			1. Integrate new product NG2 [RedmindID: #63460]
			2. Clean code of Cockfighting
		- 20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]  
		- 20170627@Cherry: Integrate Lottery and Betradar Virtual Sports (#78184, 78495)
		- 20170825@Cherry: Integrate Lucky 3 (#78214)
		- 20171030@Kean: Integrate Bullfighting (#85712)
		- 20171109@Kean: HotFix #86404 - List of Currencies is passed incorrectly
		- 20180411@Franklin: Integrate Pragmatic (#92642)
		- 20180831@Cherry: Integrate Poker Games into NAP Report (#97830)
		- 20181219@Robert: NAP Report - Add new sporttype for Happy 5 (#104253) 
		- 20190128@Robert: Video Poker - Integrate into NAP Reports[#107706]
		- 20190917@Dominic: Remove inactive products [#120215]
		- 20200313@Ned.Le: NAP Report - Incorporate Virtual Games (#130326)
		- 20200323@Ned.Le: NAP Report - Incorprorate SA Gaming (#129349) | Saba.club (#130776) | Sexy Gaming (#130853)
		- 20200331@Ned.Le: NAP Report - Incorporate new Table Games (#131095)
		- 20200409@Ned.Le: NAP Report - Incorporate BBIN Live Casino (#131357)
		- 20200422@Ned.Le: NAP Report - Incorporate IBCBet Live Casino (#132961)
		- 20200522@Cherry: Nap Report - Integrate ION Live Casino (#132324) & RNG War (#132009)
		- 20200921@Jaden.Tang: NAP Report - Incorporate Joker Gaming (#131611) & WM (#131583)
		- 20201125@Cherry: Integrate GDG (#146008)
		- 20201225@Ned.Le: NAP Reports - Integrate Big Gaming (#142481)

	Param's Explanation:  
	  + @ListCurrency: The specified date used as one of the filter criterias, if its value is 'all' then no need to be filtered by currency
	  + {251:Casino (include: 251, 208, 209, 210), 151:Racing,252:Bingo,161:Number Game,162:Live Casino,180:Virtual Sports,202:Keno,245:Virtual Games
		 220: Lottery, 163: Poker Games,
		 244: SA Gaming, 200: Saba.club, 243: Sexy Gaming, 222: Table Games,
		 241: BBIN, 242: IBCBet Live Casino, 233: WM, 236: GDG, 239: BG}
*/

BEGIN
    SET NOCOUNT ON;
/*Table of real creadit super filter by currency*/

    CREATE TABLE #FiltedCreditSuper(
	    CustID         INT
	  , SuperStatus    BIT);
    DECLARE @DepositDummySuper TABLE(
	    CustID    INT);
/*Table of Super/master/Member that belong to real super above	*/

    CREATE TABLE #FiltedDownlineAcc(
	    SuperID      INT
	  , CustID       INT
	  , RoleID       INT
	  , IsDisable    BIT);
/*Get real credit super filterd by currencies	*/

    INSERT INTO @DepositDummySuper
		 SELECT custid
		 FROM dbo.Dep_CustSuper
		 UNION
		 SELECT custid
		 FROM dbo.Acc_CustDirect
		 WHERE roleid = 4;
/* DCS setting --*/

    DECLARE @bitmapOrder TABLE(
	    bitmapOrder    TINYINT); /* using for sporttype that has many settings*/

    IF @SportType IN(211)  /* Allbet*/
	BEGIN
		INSERT INTO @bitmapOrder(bitmapOrder)
			SELECT bitmapOrder
			FROM dbo.ProductStatusProfile WITH (NOLOCK)
			WHERE Sporttype = @SportType;
	END;

    DECLARE @bitmap    TINYINT; /* using for sporttype that has 1 setting*/

    IF @SportType IN(212, 213, 219, 220, 180, 245, 244, 200, 243, 222, 241, 242, 224, 225, 233, 236, 239) 
    /* Macau Games, NG2, Fishing World, Virtual Sports, Lottery, Virtual Games, SA Gaming, Saba.club, Sexy Gaming, Table Games, BBIN, IBCBet Live Casino, RNG War, ION, WM, GDG, BG */

	   BEGIN
		  SELECT @bitmap = bitmapOrder
		  FROM dbo.ProductStatusProfile WITH (NOLOCK)
		  WHERE Sporttype = @SportType;
	   END;
/* end DCS setting --*/


    INSERT INTO #FiltedCreditSuper(CustID
						   , SuperStatus)
		 SELECT ci.custid
			 , CASE
				  WHEN @sportType IN(161)
				  THEN ci.DisableNumber
				  WHEN @sportType = 202
				  THEN CASE
						 WHEN EXISTS
								   (
									  SELECT TOP 1 1
									  FROM dbo.CustGameType AS gt WITH (NOLOCK, INDEX = PK_CustGameType)
									  WHERE gt.CustID = ci.CustID
										   AND gt.IsDisabled = 0
								   )
						 THEN 0
						 ELSE 1
					  END
				  WHEN @sportType = 251
				  THEN(~ci.SyncCasino|(ci.DisableCasino))
				  WHEN @sportType = 255
				  THEN ci.DisableGoldDeluxe
				  WHEN @sportType = -1
				  THEN ci.DisableSuperLive
				  WHEN @sportType = 204
				  THEN ci.DisableColossusBet
				  WHEN @SportType IN(211)
				  THEN
					  (
						 SELECT CASE MIN(CONVERT(INT, f.value))
								  WHEN 0
								  THEN 0
								  ELSE 1
							   END
						 FROM CustProductStatus AS cps WITH (NOLOCK)
							CROSS APPLY @bitmapOrder AS b
							CROSS APPLY f_CustSetting_ProductStatusSel
							 (cps.bitmapIsDisabled, b.bitmapOrder) AS f
						 WHERE custid = ci.custid
					  )
				  WHEN @SportType IN(212, 213, 219, 220, 180, 245, 244, 200, 243, 222, 241, 242, 224, 225, 233, 236, 239)
				  THEN
					  (
						 SELECT CASE(SELECT value
								   FROM dbo.f_CustSetting_ProductStatusSel
									   (bitmapIsDisabled, @bitmap))
								  WHEN 0
								  THEN 0
								  ELSE 1
							   END
						 FROM CustProductStatus
						 WHERE custid = ci.custid
					  )
			   END
		 FROM dbo.custInfo AS ci WITH (NOLOCK)
			JOIN dbo.CustSuper AS cs WITH (NOLOCK) ON ci.custid = cs.custid
											  AND cs.IsInternal = 0
		 WHERE ci.roleid = 4
			  AND ci.Enabled = 1
			  AND ci.custid NOT IN
							   (
								  SELECT custid
								  FROM dep_custsuper WITH (NOLOCK)
							   )
			  AND
				 (@ListCurrency = 'all'
				  OR ci.currency IN
								(
								    SELECT val
								    FROM dbo.strSplit
									    (@ListCurrency, ',')
								))
			  AND ci.currency NOT IN(20, 27, 28)
			  AND ci.custid NOT IN
							   (
								  SELECT *
								  FROM @DepositDummySuper
							   )
			  AND ci.username NOT LIKE '3rdSuper%'
			  AND ci.username NOT LIKE 'STEST%'
			  AND ci.username NOT LIKE '%ACCSuper%';

    IF @ShowEnabled = 1
	  AND @ShowDisabled = 0
	   BEGIN
		  DELETE FROM #FiltedCreditSuper
		  WHERE SuperStatus = 1;
	   END;

    IF @ShowEnabled = 0
	  AND @ShowDisabled = 1
	   BEGIN
		  DELETE FROM #FiltedCreditSuper
		  WHERE SuperStatus = 0;
	   END;

    IF @ShowEnabled = 0
	  AND @ShowDisabled = 0
	   BEGIN
		  DELETE FROM #FiltedCreditSuper;
	   END;
/*Get data for downline list */
    IF @sportType IN(161)
	   BEGIN
		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , ci.roleid
				    , ci.DisableNumber
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN dbo.CustMaster AS cm WITH (NOLOCK) ON ci.custid = cm.custid
													 AND cm.IsInternal = 0
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
											  AND ci.roleid = 3
			    WHERE ci.Enabled = 1;

		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , ci.roleid
				    , ci.DisableNumber
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN dbo.CustAgent AS ca WITH (NOLOCK) ON ci.custid = ca.custid
													AND ca.IsInternal = 0
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
											  AND ci.roleid = 2
			    WHERE ci.Enabled = 1;

		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , ci.roleid
				    , ci.DisableNumber
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
											  AND ci.roleid = 1
			    WHERE ci.Enabled = 1;
	   END;

    IF @sportType IN(251)
	   BEGIN
		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , ci.roleid
				    , (~ci.SyncCasino|(ci.DisableCasino))
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN dbo.CustMaster AS cm WITH (NOLOCK) ON ci.custid = cm.custid
													 AND cm.IsInternal = 0
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
											  AND ci.roleid = 3
			    WHERE ci.Enabled = 1;

		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , ci.roleid
				    , (~ci.SyncCasino|(ci.DisableCasino))
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN dbo.CustAgent AS ca WITH (NOLOCK) ON ci.custid = ca.custid
													AND ca.IsInternal = 0
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
											  AND ci.roleid = 2
			    WHERE ci.Enabled = 1;

		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , ci.roleid
				    , (~ci.SyncCasino|(ci.DisableCasino))
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
											  AND ci.roleid = 1
			    WHERE ci.Enabled = 1;
	   END;
    
    IF @sportType = 202
	   BEGIN
		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , ci.roleid
				    , CASE
						WHEN EXISTS
								  (
									 SELECT TOP 1 1
									 FROM dbo.CustGameType AS gt WITH (NOLOCK, INDEX = PK_CustGameType)
									 WHERE gt.CustID = ci.CustID
										  AND gt.IsDisabled = 0
								  )
						THEN 0
						ELSE 1
					 END
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN dbo.CustMaster AS cm WITH (NOLOCK) ON ci.custid = cm.custid
													 AND cm.IsInternal = 0
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
											  AND ci.roleid = 3
			    WHERE ci.Enabled = 1;

		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , ci.roleid
				    , CASE
						WHEN EXISTS
								  (
									 SELECT TOP 1 1
									 FROM dbo.CustGameType AS gt WITH (NOLOCK, INDEX = PK_CustGameType)
									 WHERE gt.CustID = ci.CustID
										  AND gt.IsDisabled = 0
								  )
						THEN 0
						ELSE 1
					 END
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN dbo.CustAgent AS ca WITH (NOLOCK) ON ci.custid = ca.custid
													AND ca.IsInternal = 0
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
											  AND ci.roleid = 2
			    WHERE ci.Enabled = 1;

		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , ci.roleid
				    , CASE
						WHEN EXISTS
								  (
									 SELECT TOP 1 1
									 FROM dbo.CustGameType AS gt WITH (NOLOCK, INDEX = PK_CustGameType)
									 WHERE gt.CustID = ci.CustID
										  AND gt.IsDisabled = 0
								  )
						THEN 0
						ELSE 1
					 END
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
											  AND ci.roleid = 1
			    WHERE ci.Enabled = 1;
	   END;
/*  Gold Deluxe & Metric Gamming*/

    IF @sportType IN(-1, 255, 204)
	   BEGIN
		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , ci.roleid
				    , CASE
						WHEN @sportType = 255
						THEN ci.DisableGoldDeluxe
						WHEN @sportType = -1
						THEN ci.DisableSuperLive
						WHEN @sportType = 204
						THEN ci.DisableColossusBet
					 END
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN dbo.CustMaster AS cm WITH (NOLOCK) ON ci.custid = cm.custid
													 AND cm.IsInternal = 0
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
											  AND ci.roleid = 3
			    WHERE ci.Enabled = 1;

		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , ci.roleid
				    , CASE
						WHEN @sportType = 255
						THEN ci.DisableGoldDeluxe
						WHEN @sportType = -1
						THEN ci.DisableSuperLive
						WHEN @sportType = 204
						THEN ci.DisableColossusBet
					 END
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN dbo.CustAgent AS ca WITH (NOLOCK) ON ci.custid = ca.custid
													AND ca.IsInternal = 0
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
											  AND ci.roleid = 2
			    WHERE ci.Enabled = 1;

		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , ci.roleid
				    , CASE
						WHEN @sportType = 255
						THEN ci.DisableGoldDeluxe
						WHEN @sportType = -1
						THEN ci.DisableSuperLive
						WHEN @sportType = 204
						THEN ci.DisableColossusBet
					 END
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID
											  AND ci.roleid = 1
			    WHERE ci.Enabled = 1;
	   END;
/* Allbet, Macau Games, NG2*/

    IF @sportType IN(211)
	   BEGIN
		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , 3
				    , 1
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN dbo.CustMaster AS cm WITH (NOLOCK) ON ci.custid = cm.custid
													 AND cm.IsInternal = 0
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID/* AND ci.roleid = 3*/
			    WHERE ci.Enabled = 1
					AND ci.roleid = 3;

		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , 2
				    , 1
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN dbo.CustAgent AS ca WITH (NOLOCK) ON ci.custid = ca.custid
													AND ca.IsInternal = 0
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID /* AND ci.roleid = 2*/
			    WHERE ci.Enabled = 1
					AND ci.roleid = 2;

		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , 1
				    , 1
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID/* AND ci.roleid = 1*/
			    WHERE ci.Enabled = 1
					AND ci.roleid = 1;

		  CREATE CLUSTERED INDEX IX_CustID ON #FiltedDownlineAcc(CustID);

		  UPDATE fda
			    SET
				   fda.IsDisable = A.IsDisable
		  FROM #FiltedDownlineAcc fda
			 INNER JOIN
			  (
				 SELECT fda.CustID
					 , CASE MIN(CONVERT(INT, f.value))
						  WHEN 0
						  THEN 0
						  ELSE 1
					   END AS IsDisable
				 FROM CustProductStatus AS cps WITH (NOLOCK)
					INNER JOIN #FiltedDownlineAcc AS fda ON cps.CustID = fda.CustID
					CROSS APPLY @bitmapOrder AS b
					CROSS APPLY f_CustSetting_ProductStatusSel
					 (cps.bitmapIsDisabled, b.bitmapOrder) AS f
				 GROUP BY fda.CustID
			  ) A ON fda.CustID = A.CustID;
	   END;
/* Macau Games, NG2, Fishing World, Virtual Sports, Lottery, Virtual Games, SA Gaming, Saba.club, Sexy Gaming, Table Games, BBIN, IBCBet Live Casino, RNG War, ION, WM, GDG, BG */

    IF @sportType IN(212, 213, 219, 220, 180, 245, 244, 200, 243, 222, 241, 242, 224, 225, 233, 236, 239)
	   BEGIN
		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , 3
				    ,
					 (
						SELECT CASE(SELECT value
								  FROM dbo.f_CustSetting_ProductStatusSel
									  (bitmapIsDisabled, @bitmap))
								 WHEN 0
								 THEN 0
								 ELSE 1
							  END
						FROM CustProductStatus
						WHERE custid = ci.custid
					 )
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN dbo.CustMaster AS cm WITH (NOLOCK) ON ci.custid = cm.custid
													 AND cm.IsInternal = 0
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID/* AND ci.roleid = 3*/
			    WHERE ci.Enabled = 1
					AND ci.roleid = 3;

		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , 2
				    ,
					 (
						SELECT CASE(SELECT value
								  FROM dbo.f_CustSetting_ProductStatusSel
									  (bitmapIsDisabled, @bitmap))
								 WHEN 0
								 THEN 0
								 ELSE 1
							  END
						FROM CustProductStatus
						WHERE custid = ci.custid
					 )
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN dbo.CustAgent AS ca WITH (NOLOCK) ON ci.custid = ca.custid
													AND ca.IsInternal = 0
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID /* AND ci.roleid = 2*/
			    WHERE ci.Enabled = 1
					AND ci.roleid = 2;

		  INSERT INTO #FiltedDownlineAcc
			    SELECT sup.CustID
				    , ci.custid
				    , 1
				    ,
					 (
						SELECT CASE(SELECT value
								  FROM dbo.f_CustSetting_ProductStatusSel
									  (bitmapIsDisabled, @bitmap))
								 WHEN 0
								 THEN 0
								 ELSE 1
							  END
						FROM CustProductStatus
						WHERE custid = ci.custid
					 )
			    FROM dbo.custInfo AS ci WITH (NOLOCK)
				   JOIN #FiltedCreditSuper AS sup ON ci.srecommend = sup.CustID/* AND ci.roleid = 1*/
			    WHERE ci.Enabled = 1
					AND ci.roleid = 1;
	   END;
/*Return result*/

    SELECT cust.custid
	    , cust.username
	    , sp.SuperStatus AS IsDisable
	    , e.currency
	    , ISNULL(rs.MasterEnabled, 0) AS MasterEnabled
	    , ISNULL(rs.MasterDisabled, 0) AS MasterDisabled
	    , ISNULL(rs.AgentEnabled, 0) AS AgentEnabled
	    , ISNULL(rs.AgentDisabled, 0) AS AgentDisabled
	    , ISNULL(rs.MemberEnabled, 0) AS MemberEnabled
	    , ISNULL(rs.MemberDisabled, 0) AS MemberDisabled
    FROM #FiltedCreditSuper AS sp
	   JOIN dbo.Customer AS cust WITH (NOLOCK) ON cust.custid = sp.CustID
	   JOIN dbo.Exchange AS e WITH (NOLOCK) ON e.exchangeid = cust.currency
	   LEFT JOIN
	    (
		   SELECT dl.SuperID
			   , SUM(CASE
					   WHEN dl.IsDisable = 0
						   AND dl.RoleID = 3
					   THEN 1
					   ELSE 0
				    END) AS MasterEnabled
			   , SUM(CASE
					   WHEN dl.IsDisable = 1
						   AND dl.RoleID = 3
					   THEN 1
					   ELSE 0
				    END) AS MasterDisabled
			   , SUM(CASE
					   WHEN dl.IsDisable = 0
						   AND dl.RoleID = 2
					   THEN 1
					   ELSE 0
				    END) AS AgentEnabled
			   , SUM(CASE
					   WHEN dl.IsDisable = 1
						   AND dl.RoleID = 2
					   THEN 1
					   ELSE 0
				    END) AS AgentDisabled
			   , SUM(CASE
					   WHEN dl.IsDisable = 0
						   AND dl.RoleID = 1
					   THEN 1
					   ELSE 0
				    END) AS MemberEnabled
			   , SUM(CASE
					   WHEN dl.IsDisable = 1
						   AND dl.RoleID = 1
					   THEN 1
					   ELSE 0
				    END) AS MemberDisabled
		   FROM #FiltedDownlineAcc AS dl
		   GROUP BY dl.SuperID
	    ) AS rs ON sp.CustID = rs.SuperID
    ORDER BY cust.username
		 , e.currency;
/*Drop temp tables*/

    DROP TABLE #FiltedCreditSuper;
    DROP TABLE #FiltedDownlineAcc;
END;
GO
