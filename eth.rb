class Eth

  POOLS = SymMash.new(
    binance: {
      url:  'https://pool.binance.com/en/statistics?urlParams=%{w}',
      api:  'https://pool.binance.com/mining-api/v1/public/pool/profit/miner?observerToken=%{w}&pageSize=20',
      read:  -> i {
        data = get i.api, w: i.wallet
        data.data.accountProfits.map do |d|
          d = SymMash.new d
          SymMash.new(
            read_at:  Time.at(d.time / 1000),
            balance:  d.profitAmount,
            hashrate: d.dayHashRate / 1.0e6,
          )
        end
      },
      db_parse: -> data {
        data.flat_map do |d|
          dr = {
            coin:              d.coin,
            pool:              d.pool,
            wallet:            d.wallet,
            read_at:           d.read_at,
            reported_hashrate: d.hashrate,
            balance:           d.balance,
          }
          dr0 = dr.merge(
            read_at: d.read_at - 24.hours + 1.minute,
            balance: 0,
          )
          [dr0, dr]
        end

      }
    },
    ezil: {
      url:      'https://ezil.me/personal_stats?wallet=%{w}&coin=eth',
      balance:  'https://billing.ezil.me/balances/%{w}',
      hashrate: 'https://stats.ezil.me/current_stats/%{w}/reported',
      read: -> i {
        SymMash.new(
          balance:  get(i.balance, w: i.wallet).eth,
          hashrate: get(i.hashrate, w: i.wallet).reported_hashrate / 1.0e6,
        )
      },
    },
    crazypool: {
      url:      'https://eth.crazypool.org/#/account/%{w}',
      api:      'https://eth.crazypool.org/api/accounts/%{w}',
      read:  -> i {
        data = get i.api, w: i.wallet
        SymMash.new(
          balance:  data.stats.balance / 1.0e9,
          hashrate: data.hashrate / 1.0e6,
        )
      },
    },
    garimpool: {
      url:  'https://garimpool.com.br/#/account/%{w}',
      api:  'https://garimpool.com.br/api/accounts/%{w}',
      read: -> i {
        data = get i.api, w: i.wallet
        SymMash.new(
          balance:  data.stats.balance / 1.0e9,
          hashrate: data.hashrate / 1.0e6,
        )
      },
    },
    flexpool: {
      url:      'https://flexpool.io/%{w}',
      balance:  'https://flexpool.io/api/v1/miner/%{w}/balance/',
      hashrate: 'https://flexpool.io/api/v1/miner/%{w}/stats/',
      read: -> i {
        SymMash.new(
          balance:  get(i.balance, w: i.wallet).result / 1.0e18,
          hashrate: get(i.hashrate, w: i.wallet).result.daily.reported_hashrate / 1.0e6,
        )
      },
    },
    ethermine: {
      url:  'https://ethermine.org/miners/%{w}',
      api:  'https://api.ethermine.org/miner/%{w}/dashboard',
      read: -> i {
        w = i.wallet.downcase.gsub(/^0x/, '')
        data = get(i.api, w: w).data
        # ignore bad hashrates
        return if data.currentStatistics.currentHashrate / data.currentStatistics.reportedHashrate > 2
        SymMash.new(
          balance:  data.currentStatistics.unpaid / 1.0e18,
          hashrate: data.currentStatistics.reportedHashrate / 1.0e6,
        )
      },
    },
    '2miners': {
      url:  'https://eth.2miners.com/account/%{w}',
      api:  'https://eth.2miners.com/api/accounts/%{w}',
      read: -> i {
        data = get i.api, w: i.wallet
        SymMash.new(
          balance:  data.stats.balance / 1.0e9,
          hashrate: data.hashrate / 1.0e6,
        )
      },
    },
    viabtc: {
      url:  'https://www.viabtc.com/observer/dashboard?access_key=%{w}&coin=ETH',
      api:  'https://www.viabtc.com/res/observer/home?access_key=%{w}&coin=ETH',
      read: -> i {
        data = get(i.api, w: i.wallet).data
        hashrate  = data.hashrate_1day.to_f
        hashrate *= 1000 if data.hashrate_1day.index 'G'
        SymMash.new(
          balance:  data.account_balance.to_f,
          hashrate: hashrate,
        )
      },
    },
    realpool: {
      url:  'https://realpool.com.br/?#eth/dashboard?address=%{w}',
      api:  'https://realpool.com.br:4000/api/pools/eth/miners/%{w}',
      read: -> i {
        data = get i.api, w: i.wallet
        SymMash.new(
          balance:  data.pendingBalance,
          hashrate: data.performance.workers.map{ |k,v| v.hashrate / 1.0e6 }.sum,
        )
      },
    },
    f2pool: {
      url:  'https://www.f2pool.com/eth/%{w}',
      api:  'https://api.f2pool.com/eth/%{w}',
      read: -> i {
        data = get i.api, w: i.wallet
        SymMash.new(
          balance:  data.balance,
          hashrate: data.local_hash / 1.0e6,
        )
      },
    },
    hiveon: {
      url:     'https://hiveon.net/eth?miner=%{w}',
      stats:   'https://hiveon.net/api/v1/stats/miner/%{w}/ETH',
      balance: 'https://hiveon.net/api/v1/stats/miner/%{w}/ETH/billing-acc',
      read: -> i {
        w = i.wallet.downcase.gsub(/^0x/, '')
        SymMash.new(
          balance:  get(i.balance, w: w).totalUnpaid,
          hashrate: get(i.stats, w: w).reportedHashrate.to_i / 1.0e6,
        )
      },
    },
    nanopool: {
      url:  'https://eth.nanopool.org/account/%{w}',
      api:  'https://eth.nanopool.org/api/v1/load_account/%{w}',
      read: -> i {
        data = get(i.api, w: i.wallet).data.userParams
        SymMash.new(
          balance:  data.balance,
          hashrate: data.reported,
        )
      },
    },
    sparkpool: {
      url:     'https://www.sparkpool.com/miner/%{w}/data?currency=ETH',
      balance: 'https://www.sparkpool.com/v1/bill/stats?miner=%{w}&currency=ETH',
      stats:   'https://www.sparkpool.com/v1/miner/stats?miner=%{w}&currency=ETH',
      read: -> i {
        SymMash.new(
          balance:  get(i.balance, w: i.wallet).data.balance,
          hashrate: get(i.stats, w: i.wallet).data.meanLocalHashrate24h.to_i / 1.0e6,
        )
      },
    },
  )

  def self.url pool, wallet
    POOLS[pool].url % {w: wallet}
  end

  def get url, params
    url  = url % params
    data = Mechanize.new.get url
    data = SymMash.new JSON.parse data.body
    data
  rescue => e
    puts "error #{url}: #{e.message}"
  end

  def pool_read pool, wallet
    input = POOLS[pool].merge wallet: wallet
    data  = instance_exec input, &input.read rescue SymMash.new
    return puts "#{pool}/#{wallet}: error while fetching data" unless data

    Array(data).each do |d|
      d.coin      = 'eth'
      d.pool      = pool.to_s
      d.wallet    = wallet
      d.read_at ||= Time.now
    end
    Tracked.track Array(data).first

    data
  end

  def pool_fetch pool
    wallets(pool).api_peach.map do |w|
      data  = pool_read pool, w rescue nil
      next puts "#{pool}: no data for #{w}" unless data
      puts "#{pool}: #{data.inspect}"

      data
    end.compact
  end

  def process
    POOLS.cpu_peach do |pool, opts|
      pool_process pool, opts
    end
  end

  def pool_process pool, opts = POOLS[pool]
    data = pool_fetch pool
    return if ENV['DRY']
    data = if opts.db_parse then data.flat_map{ |d| opts.db_parse.call d } else db_parse data end
    DB[:wallet_reads].insert_conflict.multi_insert data
  end

  def db_parse data
    data.map! do |d|
      {
        coin:              'eth',
        pool:              pool.to_s,
        wallet:            d.wallet,
        read_at:           d.read_at,
        reported_hashrate: d.hashrate,
        balance:           d.balance,
      }
    end
  end

  def wallets pool
    ds = DB[:wallets_tracked].where(coin: 'eth', pool: pool.to_s)
    ds = ds.where{ (hashrate_last > 0) | (last_read_at >= 24.hours.ago) } unless ENV['RESCRAPE']
    ds.select_map(:wallet)
  end

end
