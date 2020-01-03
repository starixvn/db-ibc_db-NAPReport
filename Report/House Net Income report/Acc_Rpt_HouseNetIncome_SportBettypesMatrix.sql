/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="1"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_SportBettypesMatrix
/*
Creator: Robert
Date: 20191224
Task:  DHWL Letstalk - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report [125762]
DB: DBWH.bodb_dwrs

Revisions:
	20191224@Robert: Initialize SP	
Example:

EXEC [Acc_Rpt_HouseNetIncome_SportBettypesMatrix]
*/
AS
    BEGIN
	   SET NOCOUNT ON;
	   CREATE TABLE #ProductMatrix(
		   ProductPrefix        VARCHAR(20)
		 , ProductId            TINYINT
		 , SportType            SMALLINT
		 , ExcludeSportType     VARCHAR(100)
		 , ExcludeSubProduct    VARCHAR(100)
		 , Bettypes             VARCHAR(100));

	   CREATE TABLE #SportBettypesMatrix(
		   ProductPrefix    VARCHAR(20)
		 , ProductId        TINYINT
		 , SportType        SMALLINT
		 , Bettype          SMALLINT
		 , SubProduct       VARCHAR(50));

	   INSERT INTO #ProductMatrix(ProductPrefix
						   , ProductId
						   , SportType
						   , ExcludeSportType
						   , ExcludeSubProduct
						   , Bettypes)
			(
			    SELECT 'SB' AS ProductPrefix
				    , 1 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType				    
					, 'BT-Sold,BT-Bought,BT-Comm' AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'VS' AS ProductPrefix
				    , 5 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'NG' AS ProductPrefix
				    , 3 AS ProductId
				    , NULL AS SportType
				    , 164 AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT '1RNG' AS ProductPrefix
				    , 6 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT '1RNG-JP' AS ProductPrefix
				    , 6 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , '2198,2398,2998,2199,2399,2999' AS Bettypes
			    UNION ALL
			    SELECT 'RNGKeno' AS ProductPrefix
				    , 8 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'AG' AS ProductPrefix
				    , 11 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'NG2' AS ProductPrefix
				    , 23 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'CB' AS ProductPrefix
				    , 15 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'MacauG' AS ProductPrefix
				    , 22 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'GD' AS ProductPrefix
				    , 12 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'AB' AS ProductPrefix
				    , 21 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'CO' AS ProductPrefix
				    , 25 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'VS2' AS ProductPrefix
				    , 27 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'LT' AS ProductPrefix
				    , 28 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'EX' AS ProductPrefix
				    , 31 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'PP' AS ProductPrefix
				    , 32 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'H5' AS ProductPrefix
				    , 3 AS ProductId
				    , 164 AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'CC' AS ProductPrefix
				    , 34 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			    UNION ALL
			    SELECT 'SP' AS ProductPrefix
				    , 37 AS ProductId
				    , NULL AS SportType
				    , NULL AS ExcludeSportType
				    , NULL AS ExcludeSubProduct
				    , NULL AS Bettypes
			);

	   CREATE CLUSTERED INDEX CI_ProductMatrix ON #ProductMatrix(ProductId, SportType, ExcludeSportType);

	   INSERT INTO #SportBettypesMatrix(ProductPrefix
							    , ProductId
							    , SportType
							    , BetType
							    , SubProduct)
			SELECT DISTINCT 
				  p.ProductPrefix
				, sb.ProductId
				, sb.SportType
				, sb.BetType
				, sb.SubProduct
			FROM bodb02.dbo.SportBettypeMatrix AS sb WITH(NOLOCK)
			    INNER JOIN #ProductMatrix AS p ON sb.ProductID = p.ProductId
			WHERE p.ProductId = 1 AND sb.EventType IN (0,1,2,4)
				 AND sb.SubProduct NOT IN
									 (
										SELECT val
										FROM strSplit
											(p.ExcludeSubProduct, ',')
									 )
			UNION ALL
			SELECT DISTINCT 
				  p.ProductPrefix
				, sb.ProductId
				, sb.SportType
				, sb.BetType
				, sb.SubProduct
			FROM bodb02.dbo.SportBettypeMatrix AS sb WITH(NOLOCK)
			    INNER JOIN #ProductMatrix AS p ON sb.ProductID = p.ProductId
			WHERE p.ProductId = 3
				 AND p.ProductPrefix = 'NG'
				 AND sb.SportType NOT IN
									(
									    SELECT val
									    FROM strSplit
										    (p.ExcludeSportType, ',')
									)
			UNION ALL
			SELECT DISTINCT 
				  p.ProductPrefix
				, sb.ProductId
				, sb.SportType
				, sb.BetType
				, sb.SubProduct
			FROM bodb02.dbo.SportBettypeMatrix AS sb WITH(NOLOCK)
			    INNER JOIN #ProductMatrix AS p ON sb.ProductID = p.ProductId
			WHERE p.ProductId = 3
				 AND p.ProductPrefix = 'H5'
				 AND sb.SportType = 164
			UNION ALL
			SELECT DISTINCT 
				  p.ProductPrefix
				, sb.ProductId
				, sb.SportType
				, sb.BetType
				, sb.SubProduct
			FROM bodb02.dbo.SportBettypeMatrix AS sb WITH(NOLOCK)
			    INNER JOIN #ProductMatrix AS p ON sb.ProductID = p.ProductId
			WHERE p.ProductId = 6
				 AND p.ProductPrefix = '1RNG-JP'
				 AND sb.BetType IN
							    (
								   SELECT val
								   FROM strSplit
									   (p.Bettypes, ',')
							    )
			UNION ALL
			SELECT DISTINCT 
				  p.ProductPrefix
				, sb.ProductId
				, sb.SportType
				, sb.BetType
				, sb.SubProduct
			FROM bodb02.dbo.SportBettypeMatrix AS sb WITH(NOLOCK)
			    INNER JOIN #ProductMatrix AS p ON sb.ProductID = p.ProductId
			WHERE p.SportType IS NULL
				 AND p.ExcludeSportType IS NULL
				 AND p.ExcludeSubProduct IS NULL
				 AND p.Bettypes IS NULL;

	   SELECT ProductPrefix
		   , ProductId
		   , SportType
		   , Bettype
		   , SubProduct
	   FROM #SportBettypesMatrix;

	   DROP TABLE #ProductMatrix;
	   DROP TABLE #SportBettypesMatrix;
    END;
GO