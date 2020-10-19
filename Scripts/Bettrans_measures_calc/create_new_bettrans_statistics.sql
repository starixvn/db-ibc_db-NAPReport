USE bodb02

-- Help the optimizer guess statistics better
-- As data is heavily skewed towards bettype < 10 (most transactions have bet type < 10)
--
-- We can optimize SQLs by guiding the optimizer algorithm to calculate based on "bettype" instead of "winlostdate"
-- Example: "guess the variance of winlostdates inside each bettype" 
--			is much easier than 
--			"guess the variance of bettypes inside each winlostdate",
--			because variance of winlostdate is more static (number of transactions of each day is same-same for each day)
-- 
-- See SP Acc_Rpt_LeagueWL_Sporttype for implementation
CREATE STATISTICS IX_bettype ON bettrans (bettype, winlostdate)
		WHERE ruben = 1 AND statusID IN (111, 112, 113) AND currency <> 20 AND currency <> 27 AND currency <> 28
		WITH FULLSCAN