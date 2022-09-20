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
      url: 'https://etc.ethermine.org/miners/%{w}',
      api: 'https://api-etc.ethermine.org/miner/%{w}/dashboard',
    )
    
    self.pools.ezil = SymMash.new(
      url:      'https://ezil.me/personal_stats?wallet=%{w}&coin=etc',
      balance:  'https://billing.ezil.me/balances/%{w}',
      hashrate: 'https://stats.ezil.me/current_stats/%{w}/reported',
      scale:    {hr: 1.0e6},
      read: -> i {
        hr = get(i.hashrate, w: i.wallet).etc
        SymMash.new(
          balance:  get(i.balance, w: i.wallet).etc,
          hashrate: hr.reported_hashrate / i.scale.hr,
          average_hashrate: hr.average_hashrate / i.scale.hr,
        )
      },
    )

  end
end
