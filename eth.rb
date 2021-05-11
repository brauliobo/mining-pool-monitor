class Eth

  POOLS = SymMash.new(
    crazypool: {
      url:      'https://eth.crazypool.org/api/accounts/%{w}',
      process:  -> i {
        data = get i.url, w: i.wallet
        SymMash.new(
          balance:  data.stats.balance / 1.0e9,
          hashrate: data.hashrate / 1.0e6,
        )
      }
    },
    flexpool: {
      balance:  'https://flexpool.io/api/v1/miner/%{w}/balance/',
      hashrate: 'https://flexpool.io/api/v1/miner/%{w}/stats/',
      process:  -> i {
        SymMash.new(
          balance:  get(i.balance, w: i.wallet).result / 1.0e18,
          hashrate: get(i.hashrate, w: i.wallet).result.daily.reported_hashrate / 1.0e6,
        )
      },
    },
    ethermine: {
      url:     'https://api.ethermine.org/miner/%{w}/dashboard',
      process: -> i {
        w = i.wallet.downcase.gsub(/^0x/, '')
        data = get(i.url, w: w).data
        SymMash.new(
          balance:  data.currentStatistics.unpaid / 1.0e18,
          hashrate: data.currentStatistics.reportedHashrate / 1.0e6,
        )
      },
    },
    '2miners': {
      url:     'https://eth.2miners.com/api/accounts/%{w}',
      process: -> i {
        data = get i.url, w: i.wallet
        SymMash.new(
          balance:  data.stats.balance / 1.0e9,
          hashrate: data.hashrate / 1.0e6,
        )
      },
    },
    f2pool: {
      url:     'https://api.f2pool.com/eth/%{w}',
      process: -> i {
        data = get i.url, w: i.wallet
        SymMash.new(
          balance:  data.balance,
          hashrate: data.local_hash / 1.0e6,
        )
      },
    },
    hiveon: {
      stats:   'https://hiveon.net/api/v1/stats/miner/%{w}/ETH',
      balance: 'https://hiveon.net/api/v1/stats/miner/%{w}/ETH/billing-acc',
      process: -> i {
        w = i.wallet.downcase.gsub(/^0x/, '')
        SymMash.new(
          balance:  get(i.balance, w: w).totalUnpaid,
          hashrate: get(i.stats, w: w).reportedHashrate.to_i / 1.0e6,
        )
      },
    },
    nanopool: {
      url:     'https://eth.nanopool.org/api/v1/load_account/%{w}',
      process: -> i {
        data = get(i.url, w: i.wallet).data.userParams
        SymMash.new(
          balance:  data.balance,
          hashrate: data.reported,
        )
      },
    },
    sparkpool: {
      balance: 'https://www.sparkpool.com/v1/bill/stats?miner=%{w}&currency=ETH',
      stats:   'https://www.sparkpool.com/v1/miner/stats?miner=%{w}&currency=ETH',
      process: -> i {
        SymMash.new(
          balance:  get(i.balance, w: i.wallet).data.balance,
          hashrate: get(i.stats, w: i.wallet).data.meanLocalHashrate24h.to_i / 1.0e6,
        )
      },
    },
  )

  def get url, params
    data = Mechanize.new.get url % params
    data = SymMash.new JSON.parse data.body
    data
  rescue
    retry
  end

  def pool_read pool, wallet
    input = POOLS[pool].merge wallet: wallet
    data  = instance_exec input, &input.process
    raise "#{w}: hashrate 0" if data.hashrate.zero?

    data.wallet = wallet
    data
  end

  def pool_fetch pool
    wallets = ENV["WALLETS_#{pool}"].squish.split
    wallets.map do |w|
      data  = pool_read pool, w
      puts "#{pool}: #{data.to_h}"
      data
    end
  end

  def process
    reference_time = Time.now
    POOLS.each do |pool, opts|
      data = pool_fetch pool
      data.each do |d|
        DB[:wallets].insert(
          coin:              'eth',
          pool:              pool.to_s,
          wallet:            d.wallet,
          reference_time:    reference_time,
          read_at:           Time.now,
          reported_hashrate: d.hashrate,
          balance:           d.balance,
        )
      end unless ENV['DRY']
    end
  end

end
