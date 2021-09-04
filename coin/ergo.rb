module Coin
  class Ergo < Eth

    self.sym = name.upcase

    self.pools = SymMash.new
    self.pools.nanopool = Eth.pools.nanopool
    self.pools.nanopool.url.gsub! 'eth', 'ergo'
    self.pools.nanopool.api.gsub! 'eth', 'ergo'

  end
end
