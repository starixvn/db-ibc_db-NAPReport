USE bodb02

CREATE STATISTICS IX_wldate_with_common_filter ON bettrans (winlostdate, recommend)
		WHERE ruben = 1 AND statusID IN (111, 112, 113) AND currency <> 20 AND currency <> 27 AND currency <> 28
		WITH FULLSCAN