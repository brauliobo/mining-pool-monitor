module Coin
  class Chia < Base

    self.sym     = 'XCH'
    self.hr_unit = 'TB'

    self.pools = SymMash.new(
      flexpool: {
        url:      'https://flexpool.io/miner/xch/%{w}',
        balance:  'https://api.flexpool.io/v2/miner/balance?coin=xch&address=%{w}',
        hashrate: 'https://api.flexpool.io/v2/miner/workers?coin=xch&address=%{w}',
        scale:    {balance: 1.0e12, hr: 1.0e12},
        read: -> i {
          SymMash.new(
            balance:  get(i.balance, w: i.wallet).result.balance / i.scale.balance,
            hashrate: get(i.hashrate, w: i.wallet).result.sum(&:averageEffectiveHashrate) / i.scale.hr,
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
      xchpool: {
        url:   'https://explorer.xchpool.org/membersearch?singleton=%{w}',
        api:   'https://api.xchpool.org/v1/members/get?search=%{w}',
        scale: {hr: 1.0e12},
        read: -> i {
          data = get i.api, w: i.wallet
          SymMash.new(
            balance:  data.unpaidBalance.gsub('XCH ', '').to_f,
            hashrate: data.netspace / i.scale.hr,
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
      futurepool: {
        url:   'https://futurepool.io/farmer-dashboard/%{w}/stats',
        api:   'http://api.futurepool.io/v1/farmer/%{w}',
        scale: {balance: 1.0e12, hr: 1.0e12},
        read: -> i {
          data = get i.api, w: i.wallet
          SymMash.new(
            balance:  data.total_balance.to_f / i.scale.balance,
            hashrate: data.estimated_total_space.to_f / i.scale.hr,
          )
        },
      },
    )

  end
end
