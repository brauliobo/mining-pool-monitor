module Coin
  class Rvn < Eth

    self.sym = name.upcase

    self.oep_bscale = 1.0e8

    self.pools = SymMash.new

    self.pools.nanopool = Eth.pools.nanopool.deep_dup
    self.pools.nanopool.url.gsub! 'eth', 'rvn'
    self.pools.nanopool.api.gsub! 'eth', 'rvn'

    self.pools['2miners'] = Eth.pools['2miners'].deep_dup
    self.pools['2miners'].url.gsub! 'eth', 'rvn'
    self.pools['2miners'].api.gsub! 'eth', 'rvn'

    self.pools.cruxpool = Eth.pools.cruxpool.deep_dup
    self.pools.cruxpool.scale.balance = 1.0e8
    self.pools.cruxpool.url.gsub! 'eth', 'rvn'
    self.pools.cruxpool.hashrate.gsub! 'eth', 'rvn'
    self.pools.cruxpool.balance.gsub!  'eth', 'rvn'

    self.pools.flypool = SymMash.new(
      url:   'https://ravencoin.flypool.org/miners/%{w}/dashboard',
      api:   'https://api-ravencoin.flypool.org/miner/%{w}/dashboard',
      scale: {balance: 1.0e8, hr: 1.0e6},
      read: -> i {
        data = get(i.api, w: i.wallet).data
        SymMash.new(
          balance:  data.currentStatistics.unpaid / i.scale.balance,
          hashrate: data.currentStatistics.currentHashrate / i.scale.hr,
        )
      },
    )

  end
end
