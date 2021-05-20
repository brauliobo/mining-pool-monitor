create or replace view intervals as SELECT start_date::date, (start_date + '3 day'::interval)::date as end_date, row_number() over(order by start_date desc) as seq
FROM generate_series(now() - '9 days'::interval, now(), '3 day'::interval) start_date
where (start_date + '3 day'::interval)::date <= now() order by start_date desc;

drop view if exists pools, multi_periods, multi_rewards, rewards;
drop materiaLIZED view periods_materialized;
drop view periods;
create or replace view periods as
select
  p.pool,
  p.wallet,
  round((extract(epoch from p2.read_at - p.read_at) / 3600 / 12)::numeric) * 12 as period,
  i.seq as iseq,
  round((avg(extract(epoch from p2.read_at - p.read_at) / 3600)::numeric), 2) as hours,
  round((avg((p.reported_hashrate + p2.reported_hashrate) / 2)::numeric), 2) as hashrate,
  avg((24 / (extract(epoch from p2.read_at - p.read_at) / 3600))
    * ((p2.balance - p.balance) / ((p.reported_hashrate + p2.reported_hashrate) / 2))) as eth_mh_day,
  max(p.read_at::date) as interval_start,
  max(p.read_at) as first_read,
  max(p2.read_at) as second_read,
  max(p2.balance - p.balance) as reward,
  max(round(p.reported_hashrate::numeric, 2)) as first_hashrate,
  max(p.balance) as first_balance,
  max(round(p2.reported_hashrate::numeric, 2)) as second_hashrate,
  max(p2.balance) as second_balance
from wallets p
join wallets p2 on p2.pool = p.pool and p2.wallet = p.wallet and p2.balance > p.balance
 and round((extract(epoch from p2.read_at - p.read_at) / 3600 / 12)::numeric) * 12 in (12,24,72)
 and 5 > 100 * abs(p2.reported_hashrate - p.reported_hashrate)/p.reported_hashrate
join intervals i on i.end_date = p2.read_at::date and (
     (i.start_date = p.read_at::date and round((extract(epoch from p2.read_at - p.read_at) / 3600 / 12)::numeric) * 12 = 72)
  or (p.read_at::date > i.start_date) and i.seq = 1)
group by p.pool, p.wallet, period, iseq --having p2.read_at = max(p2.read_at) -- min(period - hours)
order by p.pool, p.wallet, period, iseq;

create materiaLIZED view periods_materialized as select * from periods;

create or replace view multi_periods as
select
  pool,
  wallet,                          
  period * count(period) as period,
  round(avg(hours) * count(period), 2) as hours,
  avg(eth_mh_day)::numeric as eth_mh_day
from periods_materialized
where period = 72
group by pool, wallet, period having count(period) > 1;

create or replace view multi_rewards as
select
  pool,
  period,
  round(avg(hours),2) as hours,
  round(avg(eth_mh_day)::numeric * 100000, 2) as eth_mh_day
from multi_periods
group by pool, period
order by pool, period;

create or replace view rewards as
select
  pool,
  period,
  round(avg(hours),2) as hours,
  round(avg(eth_mh_day)::numeric * 100000, 2) as eth_mh_day
from periods_materialized
where iseq = 1
group by pool, period
union select * from multi_rewards
order by pool, period;

drop view if exists pools;
create view pools as
select
  pool,
  round(avg(case when period = 12  then eth_mh_day end), 2) as "12h",
  round(avg(case when period = 24  then eth_mh_day end), 2) as "24h",
  round(avg(case when period = 72  then eth_mh_day end), 2) as "3d",
  round(avg(case when period = 144 then eth_mh_day end), 2) as "6d",
  round(avg(case when period = 216 then eth_mh_day end), 2) as "9d"
from rewards
group by pool
order by "6d" desc nulls last, "3d" desc nulls last, "24h" desc nulls last;



