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

    self.pools.cruxpool = Eth.pools.cruxpool.deep_dup
    self.pools.cruxpool.url.gsub! 'eth', 'ergo'
    self.pools.cruxpool.hashrate.gsub! 'eth', 'ergo'
    self.pools.cruxpool.balance.gsub!  'eth', 'ergo'

    self.pools.flypool = Rvn.pools.flypool.deep_dup
    self.pools.flypool.scale.balance = 1.0e9
    self.pools.flypool.url.gsub! 'ravencoin', 'ergo'
    self.pools.flypool.api.gsub! 'ravencoin', 'ergo'

    self.pools.woolypooly = Eth.pools.woolypooly.deep_dup
    self.pools.woolypooly.url.gsub! 'eth', 'erg'
    self.pools.woolypooly.api.gsub! 'eth', 'ergo'

    self.pools.herominers = SymMash.new(
      url:   'https://ergo.herominers.com/?mining_address=%{w}',
      api:   'https://ergo.herominers.com/api/stats_address?address=%{w}&recentBlocksAmount=20&longpoll=false',
      scale: {balance: 1.0e9, hr: 1.0e6},
      read:  -> i {
        data = get i.api, w: i.wallet
        SymMash.new(
          balance:  data.stats.balance.to_i / i.scale.balance,
          hashrate: data.workers.sum{ |w| w.hashrate_24h }.to_i / i.scale.hr,
        )
      },
    )

  end
end
