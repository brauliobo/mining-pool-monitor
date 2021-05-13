drop view if exists periods;
create view periods as select
  p.pool,
  p.wallet,
  round((julianday(p2.read_at) - julianday(p.read_at)) * 24, 2) as hours,
  floor(mod((julianday(p2.read_at) - julianday(p.read_at)) * 24, 12)) * 12 as period,
  round((p.reported_hashrate + p2.reported_hashrate) / 2, 2) as hashrate,
  p2.balance - p.balance as reward,
  round(p.reported_hashrate, 2)  as first_hashrate,
  p.balance  as first_balance,
  round(p2.reported_hashrate, 2) as second_hashrate,
  p2.balance as second_balance,
  p2.read_at as last_read
from wallets p
join wallets p2 on p2.pool = p.pool and p2.wallet = p.wallet and p2.read_at > p.read_at
where p.read_at > datetime('now', '-80 hour') and p2.read_at > datetime('now', '-6 hour')
  and hours >= 10 and period in (12,24,48,72)
  and second_balance > first_balance
  and 5 > 100 * abs(p2.reported_hashrate - p.reported_hashrate)/p.reported_hashrate
group by p.pool, p.wallet, period having max(p2.read_at)
order by p.pool, p.wallet, period desc;

drop view if exists rewards;
create view rewards as select
  pool,
  round(avg(hours),2) as hours,
  period,
  avg((24 / hours) * (reward / hashrate)) as eth_mh_day
from periods
group by pool, period;

drop view if exists pools;
create view pools as select
  pool,
  round(avg(case when period = 12 then eth_mh_day end), 7) as `12h`,
  round(avg(case when period = 24 then eth_mh_day end), 7) as `24h`,
  round(avg(case when period = 48 then eth_mh_day end), 7) as `48h`,
  round(avg(case when period = 72 then eth_mh_day end), 7) as `72h`
from rewards
group by pool
order by `72h` desc;

