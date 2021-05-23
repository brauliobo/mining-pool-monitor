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
drop view if exists ordered_wallet_pairs, filtered_wallet_pairs, wallet_pairs, periods;

create or replace view wallet_pairs as
select
  p.pool,
  p.wallet,
  i.seq as iseq,
  24 as period,
  extract(epoch from p2.read_at - p.read_at) / 3600 as hours,
  (p.reported_hashrate + p2.reported_hashrate) / 2 as hashrate,
  p2.balance - p.balance as reward,
  p.balance as first_balance,
  p2.balance as second_balance,
  p.read_at as first_read,
  p2.read_at as second_read
from wallet_reads p
join wallet_reads p2 on p2.pool = p.pool and p2.wallet = p.wallet and p2.balance > p.balance
 and 5  > 100 * abs(p2.reported_hashrate/p.reported_hashrate - 1)
join intervals i on p.read_at::date = i.start_date and p2.read_at::date = i.end_date
 and 75 > 100 * abs(extract(epoch from p2.read_at - p.read_at) / 3600 / 24 - 1);

CREATE OR replace VIEW filtered_wallet_pairs as
select distinct
  wp.*,
  avg(wr.reported_hashrate) filter(where wr.read_at >= wp.first_read AND wr.read_at <= wp.second_read) over(partition by wr.pool, wr.wallet, iseq) AS avg_hashrate
FROM (
  select
    row_number() over(
      partition by wp.pool, wp.wallet, iseq
      order by wp.pool, wp.wallet, iseq, abs(hours / period - 1) asc, second_read desc) as row,
    wp.*
  from wallet_pairs wp
) wp
JOIN wallet_reads wr ON wp.pool = wr.pool AND wp.wallet = wr.wallet 
where wp.row = 1;

create or replace view periods as
select
  pool,
  wallet,
  period,
  iseq,
  round(avg_hashrate)::integer as "MH",
  round(hours::numeric, 2) as hours,
  round((100000 * (24 / hours) * (reward / avg_hashrate))::numeric, 2) as eth_mh_day,
  round(reward::numeric, 5) as reward,
  round(first_balance::numeric, 5) as "1st balance",
  round(second_balance::numeric, 5) as "2nd balance",
  to_char(first_read, 'MM/DD HH24:MI') as "1st read",
  to_char(second_read, 'MM/DD HH24:MI') as "2nd read"
from filtered_wallet_pairs;

create materiaLIZED view periods_materialized as select * from periods;

create or replace view rewards as
select
  p.pool,
  wallet,
  idf.period as period,
  avg(hours * id.seq) filter(where id.period <= p.period * p.iseq) as hours,
  avg(eth_mh_day)     filter(where id.period <= p.period * p.iseq) as eth_mh_day
from periods_materialized p
join intervals_defs id on id.period <= p.period * p.iseq  --period generation
join intervals_defs idf on idf.period = p.period * p.iseq --period selection
group by p.pool, p.wallet, idf.period
order by p.pool, p.wallet, idf.period;

create view pools as
select
  row_number() over(order by avg(case when period = 216 then eth_mh_day end) desc nulls last) || '. ' || pool as pool,
  count(distinct wallet) as "TW",
  round(avg(case when period = 24  then eth_mh_day::numeric end), 2) as "1d",
  round(avg(case when period = 72  then eth_mh_day::numeric end), 2) as "3d",
  round(avg(case when period = 144 then eth_mh_day::numeric end), 2) as "6d",
  round(avg(case when period = 216 then eth_mh_day::numeric end), 2) as "9d"
from rewards
group by pool
order by avg(case when period = 216 then eth_mh_day end) desc nulls last;




