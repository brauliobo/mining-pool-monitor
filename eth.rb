class Eth

  def open_ethereum_pool_read i
    data = get i.api, w: i.wallet
    avg_hashrate = data.minerCharts.sum(&:minerHash) / data.minerCharts.size / 1.0e6  if data.minerCharts
    avg_hashrate = data.hashrateHistory.sum(&:hr) / data.hashrateHistory.size / 1.0e6 if data.hashrateHistory
    hashrate = data.hashrate/1.0e6
    hashrate = (hashrate + avg_hashrate) / 2 if avg_hashrate
    SymMash.new(
      balance:  data.stats.balance / 1.0e9,
      hashrate: hashrate,
      average_hashrate: avg_hashrate,
    )
  end

  POOLS = SymMash.new(
    minerall: {
      url:      'https://minerall.io/minerstats/%{w}',
      balance:  'https://user.minerall.io/api/statistics/last-activity/%{w}',
      hashrate: 'https://user.minerall.io/api/statistics/hashrate-chart/%{w}',
      read:  -> i {
        hashrates = get(i.hashrate, w: i.wallet)
        SymMash.new(
          balance:  get(i.balance, w: i.wallet).first.total_balance.to_f,
          hashrate: hashrates.sum{ |d| d.hashrate.to_f } / hashrates.size / 1.0e6,
        )
      },
    },
    binance: {
      url:  'https://pool.binance.com/en/statistics?urlParams=%{w}',
      api:  'https://pool.binance.com/mining-api/v1/public/pool/profit/miner?observerToken=%{w}&pageSize=30',
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
          dr  = d.dup
          dr0 = dr.merge(
            read_at: d.read_at - 24.hours + 1.minute,
            balance: 0,
          )
          [dr0, dr]
        end
      },
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
    cruxpool: {
      url:      'https://cruxpool.com/eth/miner/%{w}',
      hashrate: 'https://us3.cruxpool.com/api/eth/miner/%{w}',
      balance:  'https://us3.cruxpool.com/api/eth/miner/%{w}/balance',
      read:  -> i {
        hashrate = get(i.hashrate, w: i.wallet).data
        SymMash.new(
          balance:  get(i.balance, w: i.wallet).data.balance.to_f / 1.0e9,
          hashrate: hashrate.reportedHashrate / 1.0e6,
          average_hashrate: hashrate.avgHashrate / 1.0e6,
        )
      },
    },
    zetpool: {
      url:  'https://eth.zet-tech.eu/#/account/%{w}',
      api:  'https://eth.zet-tech.eu/api/accounts/%{w}',
      read: :open_ethereum_pool_read,
    },
    crazypool: {
      url:  'https://eth.crazypool.org/#/account/%{w}',
      api:  'https://eth.crazypool.org/api/accounts/%{w}/chart',
      read: :open_ethereum_pool_read,
    },
    besafepool: {
      url:  'https://beta.besafepool.com/dashboard.html?wallet=%{w}',
      api:  'https://beta.besafepool.com/api/accounts/%{w}',
      read: :open_ethereum_pool_read,
    },
    garimpool: {
      url:  'https://garimpool.com.br/#/account/%{w}',
      api:  'https://garimpool.com.br/api/accounts/%{w}',
      read: :open_ethereum_pool_read,
    },
    flexpool: {
      url:      'https://flexpool.io/%{w}',
      balance:  'https://flexpool.io/api/v1/miner/%{w}/balance/',
      hashrate: 'https://api.flexpool.io/v2/miner/workers?coin=eth&address=%{w}',
      read: -> i {
        SymMash.new(
          balance:  get(i.balance, w: i.wallet).result / 1.0e18,
          hashrate: get(i.hashrate, w: i.wallet).result.sum(&:reportedHashrate) / 1.0e6,
        )
      },
    },
    ethermine: {
      url:  'https://ethermine.org/miners/%{w}',
      api:  'https://api.ethermine.org/miner/%{w}/dashboard',
      read: -> i {
        w = i.wallet.downcase.gsub(/^0x/, '')
        data = get(i.api, w: w).data
        SymMash.new(
          balance:  data.currentStatistics.unpaid / 1.0e18,
          hashrate: data.currentStatistics.reportedHashrate / 1.0e6,
          current_hashrate: data.currentStatistics.currentHashrate / 1.0e6,
        )
      },
    },
    '2miners': {
      url:  'https://eth.2miners.com/account/%{w}',
      api:  'https://eth.2miners.com/api/accounts/%{w}',
      read:  :open_ethereum_pool_read,
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
          average_hashrate: data.hashes_last_day / (3600 * 24) / 1.0e6,
        )
      },
    },
    hiveon: {
      url:     'https://hiveon.net/eth?miner=%{w}',
      stats:   'https://hiveon.net/api/v1/stats/miner/%{w}/ETH',
      balance: 'https://hiveon.net/api/v1/stats/miner/%{w}/ETH/billing-acc',
      read: -> i {
        w = i.wallet.downcase.gsub(/^0x/, '')
        stats = get(i.stats, w: w)
        SymMash.new(
          balance:  get(i.balance, w: w).totalUnpaid,
          hashrate: stats.reportedHashrate.to_i / 1.0e6,
          average_hashrate: stats.hashrate24h.to_i / 1.0e6,
        )
      },
    },
    nanopool: {
      url:  'https://eth.nanopool.org/account/%{w}',
      api:  'https://eth.nanopool.org/api/v1/load_account/%{w}',
      read: -> i {
        data = get(i.api, w: i.wallet).data
        SymMash.new(
          balance:  data.userParams.balance,
          hashrate: data.userParams.reported,
          average_hashrate: data.avgHashRate.h24.to_f,
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
    puts "GET #{url}" if ENV['DEBUG']
    data = http.get url
    data = JSON.parse data.body
    data = SymMash.new data if data.is_a? Hash
    data = data.map{ |d| SymMash.new d } if data.is_a? Array
    data
  rescue => e
    puts "error #{url}: #{e.message}"
  end

  def pool_read pool, wallet
    input = POOLS[pool].merge wallet: wallet
    data  = if input.read.is_a? Symbol then method(input.read).call input else instance_exec input, &input.read end

    adata = if data.is_a? Array then data else [data] end
    adata.each do |d|
      return puts "#{pool}/#{wallet}: discarding deviating hashrate" if d.current_hashrate and high_mh_deviation? d.current_hashrate, d.hashrate

      # due to conflicting worker name in multiple miners, reported can be lower
      d.hashrate = d.average_hashrate if d.average_hashrate and high_mh_deviation? d.average_hashrate, d.hashrate

      d.coin      = 'eth'
      d.pool      = pool.to_s
      d.wallet    = wallet
      d.read_at ||= Time.now
    end
    Tracked.track adata.first

    data
  rescue => e
    puts "#{pool}/#{wallet}: #{e.message}"
  end

  def high_mh_deviation? v1, v2
    (v1/v2 - 1).abs > 1
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
    data = data.flat_map{ |d| opts.db_parse.call d } if opts.db_parse
    data = data.flat_map{ |d| d.slice(*DB[:wallet_reads].columns) }
    DB[:wallet_reads].insert_conflict.multi_insert data
  end

  def wallets pool
    ds = DB[:wallets_tracked].where(coin: 'eth', pool: pool.to_s)
    ds = ds.where{ (hashrate_last > 0) & (last_read_at >= 24.hours.ago) } unless ENV['RESCRAPE']
    ds.select_map(:wallet)
  end

  def http
    @http ||= Mechanize.new do |agent|
      agent.open_timeout = 15
      agent.read_timeout = 15
    end
  end

end
