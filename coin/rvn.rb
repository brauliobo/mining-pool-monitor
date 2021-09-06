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

    self.pools.flypool = SymMash.new(
      url: 'https://ravencoin.flypool.org/miners/%{w}/dashboard',
      api: 'https://api-ravencoin.flypool.org/miner/%{w}/dashboard',
      read: -> i {
        data = get(i.api, w: i.wallet).data
        SymMash.new(
          balance:  data.currentStatistics.unpaid / 1.0e8,
          hashrate: data.currentStatistics.currentHashrate / 1.0e6,
        )
      },
    )

  end
end
