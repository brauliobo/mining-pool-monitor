create or replace view intervals as
select
  start_date::date,
  (start_date + '1 day'::interval)::date as end_date,
  row_number() over(order by start_date desc) as seq
FROM generate_series(now() - '9 days'::interval, now(), '1 day'::interval) start_date
where (start_date + '1 day'::interval)::date <= now()
order by start_date desc;

drop view if exists pools, rewards;
drop materiaLIZED view periods_materialized;
drop view if exists periods;
create or replace view periods as
with
wallet_pairs as (
select
  row_number() over(partition by p.pool, p.wallet, floor((extract(epoch from p2.read_at - p.read_at) / 3600 / 24)), i.seq order by p.pool, p.wallet, p.read_at desc) as row,
  p.pool,
  p.wallet,
  i.seq as iseq,
  floor(extract(epoch from p2.read_at - p.read_at) / 3600 / 24) * 24 as period,
  extract(epoch from p2.read_at - p.read_at) / 3600 as hours,
  (p.reported_hashrate + p2.reported_hashrate) / 2 as hashrate,
  p2.balance - p.balance as reward,
  p.balance as first_balance,
  p2.balance as second_balance,
  p.read_at as first_read,
  p2.read_at as second_read
from wallets p
join wallets p2 on p2.pool = p.pool and p2.wallet = p.wallet and p2.balance > p.balance
 and 5 > 100 * abs(p2.reported_hashrate - p.reported_hashrate)/p.reported_hashrate
join intervals i on p.read_at::date = i.start_date and p2.read_at::date = i.end_date
 and floor(extract(epoch from p2.read_at - p.read_at) / 3600 / 24) * 24 = 24
)
select
  pool,
  wallet,
  period,
  iseq,
  round(hashrate)::integer as MH,
  round(hours::numeric, 2) as hours,
  round((100000 * (24 / hours) * (reward / hashrate))::numeric, 2) as eth_mh_day,
  round(reward::numeric, 5) as reward,
  round(first_balance::numeric, 5) as "1st_balance",
  round(second_balance::numeric, 5) as "2nd_balance",
  to_char(first_read, 'MM/DD HH24:MI') as "1st_read",
  to_char(second_read, 'MM/DD HH24:MI') as "2nd_read"
from wallet_pairs
where row = 1;

create materiaLIZED view periods_materialized as select * from periods;

create or replace view rewards as
select
  pool,
  wallet,
  id.period as period,
  avg(hours * id.seq) filter(where p.iseq <= id.seq) as hours,
  avg(eth_mh_day)     filter(where p.iseq <= id.seq) as eth_mh_day
from periods_materialized p 
join intervals_defs id on p.iseq <= id.seq
group by pool, wallet, id.period
order by pool, wallet, id.period;

drop view if exists pools;
create view pools as
select
  pool,
  round(avg(case when period = 24  then eth_mh_day::numeric end), 2) as "1d",
  round(avg(case when period = 72  then eth_mh_day::numeric end), 2) as "3d",
  round(avg(case when period = 144 then eth_mh_day::numeric end), 2) as "6d",
  round(avg(case when period = 216 then eth_mh_day::numeric end), 2) as "9d"
from rewards
group by pool
order by "9d" desc nulls last, "6d" desc nulls last, "3d" desc nulls last, "1d" desc nulls last;



