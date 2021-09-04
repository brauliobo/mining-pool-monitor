create or replace view intervals as
with initial_date as (
  select (now() - ((select max(period)/24 from intervals_defs) || ' days')::interval)::date as d
)
select
  start_date::date,
  (start_date + '1 day'::interval)::date as end_date,
  row_number() over(order by start_date desc) as seq
FROM initial_date, generate_series(initial_date.d, current_date - '1 day'::interval, '1 day'::interval) start_date
order by start_date DESC;

drop view if exists wallet_rewards cascade;
DROP materialized view if exists pairs_materialized cascade;

create or replace view wallet_rewards as
select
  r.*,
  balance - lag(balance) over (partition by r.pool, r.wallet order by r.read_at) as reward
from wallet_reads r
WHERE balance >= 0 --f2pool has a lot of negative balances
order by r.coin, r.pool, r.wallet, r.read_at desc;

create or replace view last_pairs_to_update as
select
  rs.coin, rs.pool, rs.wallet, 24 as period, i.seq as iseq,
  extract(epoch from rs.read_at - rf.read_at) / 3600 as hours,
  rf.hashrate AS first_hashrate,
  rs.hashrate AS second_hashrate,
  rf.balance  AS first_balance,
  rs.balance  AS second_balance,
  rf.read_at  AS first_read,
  rs.read_at  AS second_read
from wallets_tracked t, intervals i
join lateral (
  select * from wallet_reads rs
  where t.coin = rs.coin and t.pool = rs.pool AND t.wallet = rs.wallet and rs.read_at::date = i.end_date
    AND balance > 0
  order by rs.read_at desc
  limit 1
) as rs on true
join lateral (
  select * from wallet_reads rf
  where rf.coin = rs.coin and rf.pool = rs.pool and rf.wallet = rs.wallet and rf.read_at::date = i.start_date
    AND balance > 0
  order by abs(extract(epoch from rs.read_at - rf.read_at) / 3600 / 24 - 1) asc
  limit 1
) as rf on true
where t.hashrate_last > 0 AND t.last_read_at >= now() - '24 hours'::interval 
  and (rs.pair_24h->'last')::boolean is null;

create or replace view pairs_to_update as
select
  r.*,
  avg(wr.hashrate) as avg_hashrate,
  sum(wr.reward) as reward
from last_pairs_to_update r
join wallet_rewards wr on wr.coin = r.coin and wr.pool = r.pool and wr.wallet = r.wallet
 and wr.read_at >= r.first_read and wr.read_at <= r.second_read
 and reward > -0.02 -- some pools' balances go down
group by 1,2,3,4,5,6,7,8,9,10,11,12
order by iseq, hours desc, second_read DESC;


drop function update_last_readings;
CREATE FUNCTION update_last_readings()  RETURNS INTEGER
     LANGUAGE plpgsql SECURITY DEFINER AS $$
declare
count integer;
BEGIN
  -- reset last 2 of values
  update wallet_reads
  set pair_24h = '{}'::jsonb
  where (pair_24h->'last')::boolean IS TRUE
    and read_at >= (now() - '1 day'::interval)::date;

  -- set new last
  update wallet_reads r
  set pair_24h = json_build_object('last', true, 'hours', hours, 'reward', reward, 'avg_hashrate', avg_hashrate, 'hashrate', first_hashrate, 'balance', first_balance, 'read_at', first_read)
  from (select * from pairs_to_update) p
  where r.coin = p.coin and r.pool = p.pool and r.wallet = p.wallet and r.read_at = p.second_read
    and (pair_24h->'last')::boolean IS NULL;
  GET DIAGNOSTICS count = ROW_COUNT;

return count;
end;
$$;

SELECT update_last_readings();

create or replace view pairs_parsed as
select
  wp.coin, pool, wallet, 24 AS period, i.seq AS iseq,
  round((pair_24h->'avg_hashrate')::numeric)::integer as "MH",
  round((pair_24h->'hours')::numeric, 2) as hours,
  round((c.multiplier * (24 / (pair_24h->'hours')::numeric) * ((pair_24h->'reward')::numeric / (pair_24h->'avg_hashrate')::numeric))::numeric, 2) as eth_mh_day,
  round((pair_24h->'reward')::numeric, 5) as reward,
  round((pair_24h->'balance')::numeric, 5) as "1st balance",
  round(balance::numeric, 5) as "2nd balance",
  to_char((pair_24h->>'read_at')::timestamp, 'MM/DD HH24:MI') as "1st read",
  to_char(read_at, 'MM/DD HH24:MI') as "2nd read"
from wallet_reads wp
JOIN coins c ON c.coin = wp.coin
join intervals i on read_at::date = i.end_date
WHERE (pair_24h->'last')::boolean IS TRUE
  AND (pair_24h->'avg_hashrate')::float > 0 AND (pair_24h->'reward')::float >= 0
  AND 100*abs(hashrate / (pair_24h->'avg_hashrate')::float - 1) < 10;

create materialized view pairs_materialized as select * from pairs_parsed;

create or replace view grouped_periods as
select
  pid.coin, pid.pool, pid.wallet, id.period,
  avg(pid.eth_mh_day) AS eth_mh_day,
  avg(pid."MH") as hashrate,
  sum(pid.hours) as hours,
  sum(pid.reward) as reward,
  min(pid.iseq) as iseq_min,
  max(pid.iseq) as iseq_max,
  count(distinct pid.iseq) as iseq_count
from pairs_materialized p
join intervals_defs id on true
join pairs_materialized pid on pid.coin = p.coin and pid.pool = p.pool and pid.wallet = p.wallet and id.period >= pid.period * pid.iseq
group by pid.coin, pid.pool, pid.wallet, id.period
order by pid.coin, pid.pool, pid.wallet, id.period;

create or replace view rewards as
select
  coin, pool, wallet, b.period,
  avg(eth_mh_day) AS eth_mh_day
from grouped_periods b
join intervals_defs id on id.period = b.period
-- for multiple periods consider data starting at least on 2/3 and a minimum of half data points
where (iseq_max = 1 AND b.period = 24) OR (iseq_max >= round(id.seq * 2/3) and iseq_count >= round(id.seq / 2))
group by coin, pool, wallet, b.period
order by coin, pool, wallet, b.period;



