delete from wallet_reads where (pool,wallet) in (select pool,wallet from (select wt.pool, wt.wallet, row_number() over(partition by wt.pool, lower(wt.wallet) order by started_at desc) as row from wallets_tracked wt) q where q.row > 1);

delete from wallets_tracked where (pool,wallet) in (select pool,wallet from (select wt.pool, wt.wallet, row_number() over(partition by wt.pool, lower(wt.wallet) order by started_at desc) as row from wallets_tracked wt) q where q.row > 1);
