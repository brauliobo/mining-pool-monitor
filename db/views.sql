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
select
  p.pool,
  p.wallet,
  floor((extract(epoch from p2.read_at - p.read_at) / 3600 / 24)::numeric) * 24 as period,
  i.seq as iseq,
  round((avg(extract(epoch from p2.read_at - p.read_at) / 3600)::numeric), 2) as hours,
  round((avg((p.reported_hashrate + p2.reported_hashrate) / 2)::numeric), 2) as hashrate,
  avg((24 / (extract(epoch from p2.read_at - p.read_at) / 3600))
    * ((p2.balance - p.balance) / ((p.reported_hashrate + p2.reported_hashrate) / 2))) as eth_mh_day,
  avg(p2.balance - p.balance) as reward,
  avg(p.balance) as first_balance,
  avg(p2.balance) as second_balance,
  max(p.read_at) as first_read,
  max(p2.read_at) as second_read
from wallets p
join wallets p2 on p2.pool = p.pool and p2.wallet = p.wallet and p2.balance > p.balance
 and 5 > 100 * abs(p2.reported_hashrate - p.reported_hashrate)/p.reported_hashrate
join intervals i on p.read_at::date = i.start_date and p2.read_at::date = i.end_date
 and floor((extract(epoch from p2.read_at - p.read_at) / 3600 / 24)::numeric) * 24 = 24
group by p.pool, p.wallet, period, iseq
order by p.pool, p.wallet, period, iseq;

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
  round(avg(case when period = 24  then eth_mh_day::numeric*100000 end), 2) as "1d",
  round(avg(case when period = 72  then eth_mh_day::numeric*100000 end), 2) as "3d",
  round(avg(case when period = 144 then eth_mh_day::numeric*100000 end), 2) as "6d",
  round(avg(case when period = 216 then eth_mh_day::numeric*100000 end), 2) as "9d"
from rewards
group by pool
order by "9d" desc nulls last, "6d" desc nulls last, "3d" desc nulls last, "1d" desc nulls last;



