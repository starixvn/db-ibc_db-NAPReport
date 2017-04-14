
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  User Defined Function dbo.f_DirectAgencyList    Script Date: 10/1/2014 5:21:20 PM ******/

CREATE FUNCTION [dbo].[f_DirectAgencyList]
(	
	@roleID		TINYINT
	
)
RETURNS @CustList TABLE 
(	
	CustID			INT PRIMARY KEY,
	username		VARCHAR(50),
	currency		INT,
	srecommend		INT	DEFAULT 0 
	 
)
AS
/*	Created: Jamie
	Date: 2009-07-16
	Task: Get custid of direct agency via roleid 
	DB: DBACC/BODB02
	Revisions:	
	- 20090722@Henry: Get downline list based on roleID
	- 20091001@Jamie: Get direct agency from Acc_CustDirect table
	- 20100112@Jamie: Return currency ID instead of currency Name 
	- 20130224@Lukas: move table Acc_CustDirect to new database bodb_ACC
    - 20140930@Logan:   1. Move table Acc_CustDirect to bodb02
                        2. Exclude accounts that exist in Acc_CustDirect
*/
BEGIN
	IF @roleID = 4 
	BEGIN 
		INSERT INTO @CustList(custid, username, currency, srecommend) 
		SELECT c.custid
             , c.username
             , c.currency
             , c.srecommend
		  FROM custinfo c WITH(NOLOCK)
	INNER JOIN dbo.Acc_CustDirect d WITH(NOLOCK) ON c.srecommend = d.custid 
		 WHERE c.roleid = 3
		   AND d.roleid = 4
           AND NOT EXISTS (SELECT 1
                             FROM dbo.Acc_CustDirect d1 WITH(NOLOCK)
                            WHERE c.custid = d1.custid
                          )
	END
	ELSE IF @roleID = 3 
	BEGIN
		INSERT INTO @CustList(custid, username, currency)
		SELECT c.custid
             , c.username
             , c.currency 
		  FROM custinfo c WITH(NOLOCK)
    INNER JOIN dbo.Acc_CustDirect d WITH(NOLOCK) ON c.mrecommend = d.custid 
		 WHERE c.roleid = 2
		   AND d.roleid = 3
           AND NOT EXISTS (SELECT 1
                             FROM dbo.Acc_CustDirect d1 WITH(NOLOCK)
                            WHERE c.custid = d1.custid
                          )
	END
	ELSE IF @roleID = 2 
	BEGIN
		INSERT INTO @CustList(	custid, username, currency) 
		SELECT c.custid
             , c.username
             , c.currency
		  FROM custinfo c WITH(NOLOCK)
	INNER JOIN dbo.Acc_CustDirect d WITH(NOLOCK) ON c.recommend = d.custid 
		 WHERE c.roleid = 1
		   AND d.roleid = 2
           AND NOT EXISTS (SELECT 1
                             FROM dbo.Acc_CustDirect d1 WITH(NOLOCK)
                            WHERE c.custid = d1.custid
                          )
	END 
	RETURN
END 






GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT SELECT ON [dbo].[f_DirectAgencyList] TO [vnteam]
GO 
 GRANT VIEW DEFINITION ON [dbo].[f_DirectAgencyList] TO [vnteam]
GO 
