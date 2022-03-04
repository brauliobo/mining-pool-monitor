module Coin
  class Etc < Eth

    self.sym = name.upcase

    self.pools = Eth.pools.deep_dup

    self.pools.zetpool.url.gsub! 'eth', 'etc'
    self.pools.zetpool.api.gsub! 'eth', 'etc'

    self.pools.crazypool.url.gsub! 'eth', 'etc'
    self.pools.crazypool.api.gsub! 'eth', 'etc'

    self.pools.cruxpool.url.gsub! 'eth', 'etc'
    self.pools.cruxpool.hashrate.gsub! 'eth', 'etc'
    self.pools.cruxpool.balance.gsub!  'eth', 'etc'

    self.pools.flypool = Eth.pools.ethermine.merge(
      url:  'https://etc.ethermine.org/miners/%{w}',
      api:  'https://api-etc.ethermine.org/miner/%{w}/dashboard',
    )

  end
end
