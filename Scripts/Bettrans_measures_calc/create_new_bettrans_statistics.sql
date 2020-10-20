USE bodb02

-- Help the optimizer guess statistics better
CREATE STATISTICS IX_bettype ON bettrans (bettype, winlostdate)
		WHERE ruben = 1 AND statusID IN (111, 112, 113) AND currency <> 20 AND currency <> 27 AND currency <> 28
		WITH FULLSCAN