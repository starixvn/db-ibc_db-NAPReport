ALTER PROCEDURE [dbo].[Task_BalanceCompany_HistoryIns]
AS
/*	Created: Phuc
	Date: 2010-04-28
	Task: used for company balance difference report 
	DB: DB052.bodb_CustomerLog 
	
	Revisions:
*/

SET NOCOUNT ON 
DECLARE @BalanceUpDay SMALLDATETIME
SET @BalanceUpDay = DATEADD(DAY,-7,CONVERT(VARCHAR(10), CURRENT_TIMESTAMP, 120))

IF (DATEPART(weekday,@BalanceUpDay)<> 6)
BEGIN
    PRINT 'Today is not Friday'
    SELECT 'Today is not Friday' RESULT
    RETURN
END

IF NOT EXISTS(
    SELECT 1
    FROM
    (
        SELECT
            SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*(b.actualrate - e.actualrate)) diff
        FROM bodb02.dbo.bettrans b WITH (READPAST)
            INNER JOIN bodb02.dbo.custinfo ci (READPAST) ON b.custid = ci.custid
            INNER JOIN bodb02.dbo.exchange e (READPAST) ON ci.currency = e.exchangeid
        WHERE
            ruben=1 AND winlostdate <= @BalanceUpDay
    ) a
    WHERE ABS(a.diff) > 0.01
)
BEGIN
    PRINT 'No difference'
    SELECT 'No difference' RESULT
    RETURN
END

IF EXISTS(SELECT 1 FROM CompanyBalance_History (READPAST) WHERE BalanceUpDay = @BalanceUpDay)
BEGIN
    DELETE FROM CompanyBalance_History WHERE BalanceUpDay = @BalanceUpDay
END

INSERT INTO CompanyBalance_History(BalanceUpDay, Currency, CompBalBefore, CompBalAfter)
SELECT    
    @BalanceUpday AS BalanceUpday,
    exchangeid AS currency,
    SUM( (winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)* b.actualrate) CompBalBefore,
    SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)* e.actualrate) CompBalAfter
FROM bodb02.dbo.bettrans b WITH (READPAST)
    INNER JOIN bodb02.dbo.custinfo ci (READPAST) ON b.custid = ci.custid
    INNER JOIN bodb02.dbo.exchange e (READPAST) ON ci.currency = e.exchangeid
WHERE
    ruben=1 AND winlostdate <= @BalanceUpday
GROUP BY  exchangeid

go
GRANT VIEW DEFINITION ON [dbo].[Task_BalanceCompany_HistoryIns] TO [vnteam]
