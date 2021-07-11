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

drop view if exists grouped_periods, grouped_rewards, rewards;
drop materiaLIZED view periods_materialized;
drop view if exists wallet_rewards, last_reads, filtered_wallet_pairs, wallet_pairs, periods;

create or replace view wallet_rewards as
select 
  r.*,
  balance - lag(balance) over (partition by r.pool, r.wallet order by r.read_at) as reward
from wallet_reads r 
order by r.pool, r.wallet, r.read_at desc;

create or replace view last_reads as
select
  row_number() over(
    partition by r.pool, r.wallet, i.seq
    order by r2.read_at DESC
  ) as row,
  r.pool,
  r.wallet,
  i.seq as iseq,
  24 as period,
  extract(epoch from r2.read_at - r.read_at) / 3600 as hours,
  r.hashrate  AS first_hashrate,
  r2.hashrate AS second_hashrate,
  r.balance   AS first_balance,
  r2.balance  AS second_balance,
  r.read_at   AS first_read,
  r2.read_at  AS second_read
from wallet_reads r
JOIN wallets_tracked t ON t.pool = r.pool AND t.wallet = r.wallet AND t.hashrate_last > 0 
join wallet_reads r2 on r2.pool = r.pool and r2.wallet = r.wallet 
join intervals i on r.read_at::date = i.start_date and r2.read_at::date = i.end_date
 and 100*abs(extract(epoch from r2.read_at - r.read_at) / 3600 / 24 - 1) < 50;

create or replace view wallet_pairs as
select
  r.*,
  avg(wr.hashrate) as avg_hashrate,
  sum(wr.reward) as reward
  
from last_reads r
join wallet_rewards wr on wr.pool = r.pool and wr.wallet = r.wallet and wr.read_at >= r.first_read and wr.read_at <= r.second_read and reward > 0
where row = 1
group by 1,2,3,4,5,6,7,8,9,10,11,12
order by iseq, hours desc, second_read DESC;

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
from wallet_pairs
WHERE 100*abs(second_hashrate/avg_hashrate - 1) < 10;

create materialized view periods_materialized as select * from periods;

create or replace view grouped_periods as
   select 
    pid.pool, pid.wallet, id.period,
--    avg(pid.eth_mh_day) AS eth_mh_day,
    percentile_cont(0.5) WITHIN GROUP (ORDER by pid.eth_mh_day) as eth_mh_day,
    avg(pid."MH") as hashrate,
    sum(pid.hours) as hours,
    sum(pid.reward) as reward,
    min(pid.iseq) as iseq_min,
    max(pid.iseq) as iseq_max,
    count(distinct pid.iseq) as iseq_count
  from periods_materialized p
  join intervals_defs id on true
  join periods_materialized pid on pid.pool = p.pool and pid.wallet = p.wallet and id.period >= pid.period * pid.iseq
  group by pid.pool, pid.wallet, id.period
  order by pid.pool, pid.wallet, id.period;

-- not working yet, as it is potencially grouping different hashrates
create or replace view grouped_rewards as
  select  
    pool, wallet, period,
    reward, hours, hashrate,
    iseq_min, iseq_max, iseq_count,
    avg((100000 * (24 / hours) * (reward / hashrate))::numeric) over(partition by pool, wallet, period) as eth_mh_day
  from grouped_periods gp;
 
create or replace view rewards as
select
  pool,
  wallet,
  b.period,
  --avg(eth_mh_day) AS eth_mh_day
  percentile_cont(0.5) WITHIN GROUP (ORDER by eth_mh_day) as eth_mh_day
from grouped_periods b
join intervals_defs id on id.period = b.period
-- for multiple periods consider data starting at least on 2/3 and a minimum of half data points
where (iseq_max = 1 AND b.period = 24) OR (iseq_max >= round(id.seq * 2/3) and iseq_count >= round(id.seq / 2))
group by pool, wallet, b.period 
order by pool, wallet, b.period;



