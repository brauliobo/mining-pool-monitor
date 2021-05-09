drop view if exists recent_points;
create view recent_points as 
  select
    pool,
    wallet,
    balance,
    reported_hashrate,
    read_at,
    row_number() over (partition by pool,wallet order by read_at asc) as row
  from wallets
  where reported_hashrate > 0
    and balance > 0
    and read_at > datetime('now', '-48 hour');

drop view if exists balances;
create view balances as 
  select
    p.pool,
    p.wallet,
    round((julianday(p2.read_at) - julianday(p.read_at)) * 24, 1) as hours,
    round((p.reported_hashrate + p2.reported_hashrate) / 2, 1) as hashrate,
    p.reported_hashrate  as first_hashrate,
    p2.reported_hashrate as second_hashrate,
    p.balance  as first_balance,
    p2.balance as second_balance,
    p.read_at  as first_read_at,
    p2.read_at as second_read_at
  from recent_points p
  join recent_points p2 on p2.pool = p.pool and p2.wallet = p.wallet
   and p.row == 1 and p2.row > p.row
  where second_balance > first_balance 
    and abs(p2.reported_hashrate - p.reported_hashrate)/p.reported_hashrate < 0.01
  group by p.pool, p.wallet, hours;

drop view if exists rewards;
create view rewards as 
  select
    pool,
    wallet,
    second_read_at as last_read_at,
    hours,
    hashrate,
    second_balance - first_balance as reward
  from balances
  group by pool, wallet, hours;

drop view if exists readings;
create view readings as 
  select
    pool,
    wallet,
    hashrate,
    last_read_at,
    hours,
    reward / hashrate as reward_per_mh
  from rewards
  group by pool, wallet, hours;

drop view if exists last_readings;
create view last_readings as 
  select r.*
  from readings r
  left join readings r2 on r2.pool = r.pool and r2.wallet = r.wallet and r2.last_read_at > r.last_read_at
  where r2.last_read_at is null and r.hours > 1;

