class Eth

  POOLS = Hashie::Mash.new(
    flexpool: {
      balance:  'https://flexpool.io/api/v1/miner/%{w}/balance/',
      hashrate: 'https://flexpool.io/api/v1/miner/%{w}/stats/',
      process:  -> i {
        Hashie::Mash.new(
          balance:  get(i.balance, w: i.wallet).result / 1.0e18,
          hashrate: get(i.hashrate, w: i.wallet).result.daily.reported_hashrate / 1.0e6,
        )
      },
    },
    ethermine: {
      url:     'https://api.ethermine.org/miner/%{w}/dashboard',
      process: -> i {
        data = get(i.url, w: i.wallet).data
        Hashie::Mash.new(
          balance:  data.currentStatistics.unpaid / 1.0e18,
          hashrate: data.currentStatistics.reportedHashrate / 1.0e6,
        )
      },
    },
    eth2miners: {
      url:     'https://eth.2miners.com/api/accounts/%{w}',
      process: -> i {
        data = get i.url, w: i.wallet
        Hashie::Mash.new(
          balance:  data.stats.balance / 1.0e9,
          hashrate: data.hashrate / 1.0e6,
        )
      },
    },
    f2pool: {
      url:     'https://api.f2pool.com/eth/%{w}',
      process: -> i {
        data = get i.url, w: i.wallet
        Hashie::Mash.new(
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
        Hashie::Mash.new(
          balance:  get(i.balance, w: w).totalUnpaid,
          hashrate: get(i.stats, w: w).hashrate.to_i / 1.0e6,
        )
      },
    },
    nanopool: {
      url:     'https://eth.nanopool.org/api/v1/load_account/%{w}',
      process: -> i {
        data = get(i.url, w: i.wallet).data.userParams
        Hashie::Mash.new(
          balance:  data.balance,
          hashrate: data.reported,
        )
      },
    },
    sparkpool: {
      balance: 'https://www.sparkpool.com/v1/bill/stats?miner=%{w}&currency=ETH',
      stats:   'https://www.sparkpool.com/v1/miner/stats?miner=%{w}&currency=ETH',
      process: -> i {
        Hashie::Mash.new(
          balance:  get(i.balance, w: i.wallet).data.balance,
          hashrate: get(i.stats, w: i.wallet).data.meanLocalHashrate24h.to_i / 1.0e6,
        )
      },
    },
  )

  def get url, params
    data = Mechanize.new.get url % params
    data = Hashie::Mash.new JSON.parse data.body
    data
  end

  def pool_fetch pool, opts = POOLS.eth[pool]
    wallets = ENV["WALLETS_#{pool}"].squish.split
    wallets.map do |w|
      input = opts.merge wallet: w
      data  = instance_exec input, &opts.process
      raise "#{w}: hashrate 0" if data.hashrate.zero?
      data.wallet = w

      puts "#{pool}: #{data.to_h}"
      data
    end
  end

  def process
    reference_time = Time.now
    POOLS.each do |pool, opts|
      data = pool_fetch pool, opts
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
