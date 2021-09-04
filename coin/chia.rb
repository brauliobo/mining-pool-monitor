module Coin
  class Chia < Base

    self.sym     = 'XCH'
    self.hr_unit = 'TB'

    self.pools = SymMash.new(
      flexpool: {
        url:      'https://flexpool.io/miner/xch/%{w}',
        balance:  'https://api.flexpool.io/v2/miner/balance?coin=xch&address=%{w}',
        hashrate: 'https://api.flexpool.io/v2/miner/workers?coin=xch&address=%{w}',
        read: -> i {
          SymMash.new(
            balance:  get(i.balance, w: i.wallet).result.balance / 1.0e12,
            hashrate: get(i.hashrate, w: i.wallet).result.sum(&:averageEffectiveHashrate) / 1.0e12,
          )
        },
      },
      spacepool: {
        url:  'https://pool.space/account/%{w}',
        api:  'https://pool.space/api/farms/%{w}',
        read: -> i {
          data = get i.api, w: i.wallet
          SymMash.new(
            balance:  data.unpaidBalanceInXCH,
            hashrate: data.estimatedPlotSizeTiB,
          )
        },
      },
      corepool: {
        url: 'https://chia.core-pool.com/farmer/%{w}',
        read: -> i {
          get i.url, w: i.wallet
          # getting 503 due to cloudflare
          SymMash.new(
            balance:  nil,
            hashrate: nil,
          )
        },
      },
    )

  end
end
