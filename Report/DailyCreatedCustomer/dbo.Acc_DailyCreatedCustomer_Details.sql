
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.Acc_DailyCreatedCustomer_Details    Script Date: 10/7/2014 10:42:40 AM ******/

CREATE PROCEDURE [dbo].[Acc_DailyCreatedCustomer_Details]
	@Date DATETIME,
	@RoleID INT,
	@IsDirect BIT  = 1
AS

/*	Creator: Simon
		Date: 2009-12-08
		Task: Daily Created Customers Detail Report
		DB: DBACC/bodb02		
		
		Revisions:
			- 20130224@Lukas: move table Acc_CustDirect to new database bodb_ACC
			- 20131106@Kathy: [Redmine:#6837]
					+ Add @IsDirect
					+ Add Master, Agent, Member's detail
            - 20140930@Logan:   Use f_DirectAgencyList instead of Acc_CustDirect
*/	
BEGIN
    SET NOCOUNT ON

    SET @Date = CONVERT(CHAR(10), @Date, 120)

    -- Super List
    if (@RoleID=4)  
    Begin
	    SELECT c.custid, c.username, c.creatdate, o.username creator
	    FROM customer c WITH (NOLOCK)
		    LEFT JOIN CustInfo o with(nolock) on o.custid = c.Creator  
	    WHERE c.RoleID = 4
		    AND CONVERT(CHAR(10),c.creatdate,120) = @Date
	    Order BY c.creatdate DESC, c.username
    End
    -- Direct Master & Master list
    ELSE IF (@RoleID = 3) 
    BEGIN
	    IF @IsDirect = 1
	    BEGIN
		    SELECT c.custid
                 , c.username
                 , c.creatdate
                 , o.username creator
		      FROM f_DirectAgencyList(4) r
         LEFT JOIN customer c WITH(NOLOCK) ON c.custid = r.custid 
		 LEFT JOIN CustInfo o WITH(NOLOCK) ON o.custid = c.Creator  
		    WHERE c.RoleID = 3
		      AND CONVERT(CHAR(10), c.creatdate, 120) = @Date
		 ORDER BY c.creatdate DESC, c.username

	    END
	    ELSE IF @IsDirect = 0
	    BEGIN
		    SELECT c.custid, c.username, c.creatdate, ci.username as creator
		    FROM Customer c with(NOLOCK)
		    Left JOIN custInfo ci WITH(NOLOCK) ON ci.custid = c.creator
		    where c.roleid = 3
			    AND c.srecommend not in (SELECT r.custid FROM dbo.Acc_CustDirect r  WITH (NOLOCK) WHERE r.roleid = 4)
			    AND CONVERT(CHAR(10),c.creatdate,120) = @Date
		    ORDER BY c.creatdate DESC, c.username
	    END
    END
    -- Direct Agent & Agent list
    ELSE IF @RoleID = 2
    BEGIN
	    IF @IsDirect = 1
	    BEGIN

		    SELECT c.custid
                 , c.username
                 , c.creatdate
                 , o.username creator
		      FROM f_DirectAgencyList(3) r
	     LEFT JOIN customer c WITH(NOLOCK) ON c.custid = r.custid 
		 LEFT JOIN CustInfo o WITH(NOLOCK) ON o.custid = c.Creator  
		    WHERE c.RoleID = 2
		      AND CONVERT(CHAR(10), c.creatdate, 120) = @Date
		 ORDER BY c.creatdate DESC, c.username

	    END
	    ELSE IF @IsDirect = 0
	    BEGIN
		    SELECT c.custid, c.username, c.creatdate, ci.username as creator
		    FROM Customer c with(NOLOCK)
		    Left JOIN custInfo ci WITH(NOLOCK) ON ci.custid = c.creator
		    where c.roleid = 2
			    and c.mrecommend not in (SELECT r.custid FROM dbo.Acc_CustDirect r  WITH (NOLOCK) WHERE r.roleid = 3)
			    and  CONVERT(CHAR(10),c.creatdate,120) = @Date
		    Order BY c.creatdate DESC, c.username
	    END
    End
    ELSE IF @RoleId = 1 -- Member list
    BEGIN
	    SELECT c.custid, c.username, c.creatdate, ci.username as creator
		    FROM Customer c with(NOLOCK)
		    Left JOIN custInfo ci WITH(NOLOCK) ON ci.custid = c.creator
		    where c.roleid = 1
			    and  CONVERT(CHAR(10),c.creatdate,120) = @Date
		    Order BY c.creatdate DESC, c.username
    END
END



GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_DailyCreatedCustomer_Details] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_DailyCreatedCustomer_Details] TO [bodbAdminNet]
GO 
