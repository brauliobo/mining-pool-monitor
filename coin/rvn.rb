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

  end
end
