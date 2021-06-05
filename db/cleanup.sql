delete from wallet_reads where (coin,pool,wallet,read_at) in (
select
  wr.coin,wr.pool,wr.wallet,wr.read_at
from wallet_reads wr
left join filtered_wallet_pairs wp on wp.pool = wr.pool and wp.wallet = wr.wallet and (wp.first_read = wr.read_at or wp.second_read = wr.read_at)
where wp.pool is null
  and (wr.read_at >= (select min(start_date) from intervals) and wr.read_at <= now() - '48 hours'::interval)
);

refresh materialized view periods_materialized;

