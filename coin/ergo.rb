module Coin
  class Ergo < Eth

    self.sym = name.upcase

    self.pools = SymMash.new
    self.pools.nanopool = Eth.pools.nanopool.deep_dup
    self.pools.nanopool.url.gsub! 'eth', 'ergo'
    self.pools.nanopool.api.gsub! 'eth', 'ergo'

    self.pools['2miners'] = Eth.pools['2miners'].deep_dup
    self.pools['2miners'].url.gsub! 'eth', 'erg'
    self.pools['2miners'].api.gsub! 'eth', 'erg'

    self.pools.merge!(
      woolypooly: {
        url:  'https://woolypooly.com/en/coin/erg/wallet/%{w}',
        api:  'https://api.woolypooly.com/api/ergo-1/accounts/%{w}',
        read: -> i {
          data = get i.api, w: i.wallet
          SymMash.new(
            balance:  data.stats.balance,
            hashrate: stats.reportedHashrate.to_i / 1.0e6,
          )
        },
      },
      herominers: {
        url:  'https://ergo.herominers.com/?mining_address=%{w}',
        api:  'https://ergo.herominers.com/api/stats_address?address=%{w}&recentBlocksAmount=20&longpoll=false',
        read: -> i {
          data = get i.api, w: i.wallet
          SymMash.new(
            balance:  data.stats.balance.to_i / 1.0e9,
            hashrate: data.workers.sum{ |w| w.hashrate_24h }.to_i / 1.0e6,
          )
        },
      },
    )

  end
end
