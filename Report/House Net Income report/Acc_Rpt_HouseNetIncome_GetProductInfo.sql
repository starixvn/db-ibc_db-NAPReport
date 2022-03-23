/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

CREATE PROCEDURE dbo.Acc_Rpt_HouseNetIncome_GetProductInfo @ProductID INT
AS

/*
    Created: 20220321@Ned.Le
    Task:    Get information about product
    DB:      DBWH/bodb_dwrs
   
    Revisions:
        20201117@Ned.Le: DHWL Email/Letstalk - Enhance the way to get product name dynamically (#170242)

    Param's Explanation:
        @ProductID: ProductID to get information

    Example:
        EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_GetProductInfo @ProductID = 42
*/

BEGIN

    SET NOCOUNT ON

    SELECT DISTINCT OrderByProduct, ProductID, AliasProductID, ProductPrefix, ProductName, ProductShortName
    FROM bodb_account.dbo.HNISettings (NOLOCK)
    WHERE ProductID = @ProductID

END
GO