module Coin
  class Etc < Eth

    self.sym = name.upcase

    self.pools = Eth.pools.dup
    self.pools.zetpool.url.gsub! 'eth', 'etc'
    self.pools.zetpool.api.gsub! 'eth', 'etc'
    self.pools.crazypool.url.gsub! 'eth', 'etc'
    self.pools.crazypool.api.gsub! 'eth', 'etc'

  end
end
