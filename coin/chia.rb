module Coin
  class Chia < Base

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
    )

  end
end
