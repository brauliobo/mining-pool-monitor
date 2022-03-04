module Coin
  class Eth < Base

    self.sym = name.upcase

    class_attribute :oep_hscale
    self.oep_hscale = 1.0e6
    class_attribute :oep_bscale
    self.oep_bscale = 1.0e9

    def open_ethereum_pool_read i
      data = get i.api, w: i.wallet

      avg_hashrate   = data.minerCharts.sum(&:minerHash) / data.minerCharts.size / oep_hscale  if data.minerCharts
      avg_hashrate ||= data.hashrate / oep_hscale

      hashrate = data.totalSubmitHashrate if data.totalSubmitHashrate
      wk_hr    = data.workers.flat_map{ |_, w| w.reportedHr || w.submithashrate || w.rhr }.sum
      hashrate = wk_hr / oep_hscale if wk_hr > 0

      SymMash.new(
        balance:  data.stats.balance / oep_bscale,
        hashrate: hashrate,
        average_hashrate: avg_hashrate,
      )
    end

    self.pools = SymMash.new(
      minerall: {
        url:      'https://minerall.io/minerstats/%{w}',
        balance:  'https://user.minerall.io/api/statistics/last-activity/%{w}',
        hashrate: 'https://user.minerall.io/api/statistics/hashrate-chart/%{w}',
        scale:    {hr: 1.0e6},
        read:  -> i {
          hashrates = get(i.hashrate, w: i.wallet)
          SymMash.new(
            balance:  get(i.balance, w: i.wallet).first.total_balance.to_f,
            hashrate: hashrates.sum{ |d| d.hashrate.to_f } / hashrates.size / i.scale.hr,
          )
        },
      },
      binance: {
        url:   'https://pool.binance.com/en/statistics?urlParams=%{w}',
        api:   'https://pool.binance.com/mining-api/v1/public/pool/profit/miner?observerToken=%{w}&pageSize=30',
        scale: {hr: 1.0e6},
        read:  -> i {
          data = get i.api, w: i.wallet
          data.data.accountProfits.map do |d|
            d = SymMash.new d
            SymMash.new(
              read_at:  Time.at(d.time / 1000),
              balance:  d.profitAmount,
              hashrate: d.dayHashRate / i.scale.hr,
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
        scale:    {hr: 1.0e6},
        read: -> i {
          hr = get(i.hashrate, w: i.wallet).eth
          SymMash.new(
            balance:  get(i.balance, w: i.wallet).eth,
            hashrate: hr.reported_hashrate / i.scale.hr,
            average_hashrate: hr.average_hashrate / i.scale.hr,
          )
        },
      },
      cruxpool: {
        url:      'https://cruxpool.com/eth/miner/%{w}',
        hashrate: 'https://cruxpool.com/api/eth/miner/%{w}',
        balance:  'https://cruxpool.com/api/eth/miner/%{w}/balance',
        scale:    {balance: 1.0e9, hr: 1.0e6},
        read:  -> i {
          hashrate = get(i.hashrate, w: i.wallet).data
          SymMash.new(
            balance:  get(i.balance, w: i.wallet).data.balance.to_f / i.scale.balance,
            hashrate: hashrate.reportedHashrate / i.scale.hr,
            average_hashrate: hashrate.avgHashrate / i.scale.hr,
          )
        },
      },
      zetpool: {
        url:  'https://zetpool.org/eth/#/account/%{w}',
        api:  'https://zetpool.org/eth/api/accounts/%{w}',
        read: :open_ethereum_pool_read,
      },
      'zetpool-pps': {
        url:  'https://zetpool.org/eth-pps/#/account/%{w}',
        api:  'https://zetpool.org/eth-pps/api/accounts/%{w}',
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
      woolypooly: {
        url:   'https://woolypooly.com/en/coin/eth/wallet/%{w}',
        api:   'https://api.woolypooly.com/api/eth-1/accounts/%{w}',
        scale: {hr: 1.0e6},
        read: -> i {
          data = get i.api, w: i.wallet
          hr   = data.perfomance.pplns.sum{ |p| p.hashrate } / data.perfomance.pplns.size
          SymMash.new(
            balance:  data.stats.balance,
            hashrate: hr / i.scale.hr,
          )
        },
      },
      flexpool: {
        url:      'https://flexpool.io/miner/eth/%{w}',
        balance:  'https://api.flexpool.io/v2/miner/balance?coin=eth&address=%{w}',
        hashrate: 'https://api.flexpool.io/v2/miner/workers?coin=eth&address=%{w}',
        scale:    {balance: 1.0e18, hr: 1.0e6},
        read: -> i {
          hr = get(i.hashrate, w: i.wallet).result
          SymMash.new(
            balance:  get(i.balance, w: i.wallet).result.balance / i.scale.balance,
            hashrate: hr.sum(&:reportedHashrate) / i.scale.hr,
            average_hashrate: hr.sum(&:averageEffectiveHashrate) / i.scale.hr,
          )
        },
      },
      ethermine: {
        url:   'https://ethermine.org/miners/%{w}',
        api:   'https://api.ethermine.org/miner/%{w}/dashboard',
        scale: {balance: 1.0e18, hr: 1.0e6},
        read: -> i {
          w = i.wallet.downcase.gsub(/^0x/, '')
          data = get(i.api, w: w).data
          SymMash.new(
            balance:  data.currentStatistics.unpaid / i.scale.balance,
            hashrate: data.currentStatistics.reportedHashrate / i.scale.hr,
            current_hashrate: data.currentStatistics.currentHashrate / i.scale.hr,
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
        url:   'https://realpool.com.br/?#eth/dashboard?address=%{w}',
        api:   'https://realpool.com.br:4000/api/pools/eth/miners/%{w}',
        scale: {hr: 1.0e6},
        read: -> i {
          data = get i.api, w: i.wallet
          SymMash.new(
            balance:  data.pendingBalance,
            hashrate: data.performance.workers.map{ |k,v| v.hashrate }.sum / i.scale.hr,
          )
        },
      },
      f2pool: {
        url:  'https://www.f2pool.com/eth/%{w}',
        api:  'https://api.f2pool.com/eth/%{w}',
        scale: {hr: 1.0e6},
        read: -> i {
          data = get i.api, w: i.wallet
          SymMash.new(
            balance:  data.balance,
            hashrate: data.local_hash / i.scale.hr,
            average_hashrate: data.hashes_last_day / (3600 * 24) / i.scale.hr,
          )
        },
      },
      hiveon: {
        url:     'https://hiveon.net/eth?miner=%{w}',
        stats:   'https://hiveon.net/api/v1/stats/miner/%{w}/ETH',
        balance: 'https://hiveon.net/api/v1/stats/miner/%{w}/ETH/billing-acc',
        scale:   {hr: 1.0e6},
        read: -> i {
          w = i.wallet.downcase.gsub(/^0x/, '')
          stats = get(i.stats, w: w)
          SymMash.new(
            balance:  get(i.balance, w: w).totalUnpaid,
            hashrate: stats.reportedHashrate.to_i / i.scale.hr,
            average_hashrate: stats.hashrate24h.to_i / i.scale.hr,
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
        scale:   {hr: 1.0e6},
        read: -> i {
          SymMash.new(
            balance:  get(i.balance, w: i.wallet).data.balance,
            hashrate: get(i.stats, w: i.wallet).data.meanLocalHashrate24h.to_i / i.scale.hr,
          )
        },
      },
    )

  end
end
