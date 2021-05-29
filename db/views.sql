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

drop view if exists rewards;
drop materiaLIZED view periods_materialized;
drop view if exists filtered_wallet_pairs, wallet_pairs, periods;

create or replace view wallet_pairs as
select
  p.pool,
  p.wallet,
  i.seq as iseq,
  24 as period,
  extract(epoch from p2.read_at - p.read_at) / 3600 as hours,
  p2.balance - p.balance as reward,
  p.reported_hashrate AS first_hashrate,
  p2.reported_hashrate AS second_hashrate,
  p.balance  AS first_balance,
  p2.balance AS second_balance,
  p.read_at  AS first_read,
  p2.read_at AS second_read
from wallet_reads p
JOIN wallets_tracked pt ON pt.pool = p.pool AND pt.wallet = p.wallet AND pt.hashrate_last > 0 
join wallet_reads p2 on p2.pool = p.pool and p2.wallet = p.wallet and p2.balance > p.balance
join intervals i on p.read_at::date = i.start_date and p2.read_at::date = i.end_date
 and 100*abs(extract(epoch from p2.read_at - p.read_at) / 3600 / 24 - 1) < 50;

CREATE OR replace VIEW filtered_wallet_pairs as
select distinct
  wp.*,
  avg(wr.reported_hashrate) filter(where wr.read_at >= wp.first_read AND wr.read_at <= wp.second_read) over(partition by wr.pool, wr.wallet, iseq) AS avg_hashrate
FROM (
  select
    row_number() over(
      partition by wp.pool, wp.wallet, iseq
      order by second_read desc, CASE WHEN first_balance = 0 THEN 0 ELSE 1 end, abs(hours / period - 1) asc) as row,
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
from filtered_wallet_pairs
WHERE 100*abs(second_hashrate/avg_hashrate - 1) < 5;

create materiaLIZED view periods_materialized as select * from periods;

create or replace view rewards as
select
  pid.pool,
  pid.wallet,
  id.period as period,
  avg(pid.hours * id.seq) as hours,
  avg(pid.eth_mh_day) as eth_mh_day
from periods_materialized p
join intervals_defs id on true
join periods_materialized pid on pid.pool = p.pool and pid.wallet = p.wallet and id.period >= pid.period * pid.iseq
group by pid.pool, pid.wallet, id.period
order by pid.pool, pid.wallet, id.period;


