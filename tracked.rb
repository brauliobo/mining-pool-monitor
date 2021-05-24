class Tracked

  def self.track data
    wt = WalletTracked.find_or_create coin: data.coin, pool: data.pool, wallet: data.wallet

    fields = SymMash.new hashrate_last: data.hashrate
    fields.last_read_at = data.read_at || Time.now if data.hashrate.to_i > 0
    wt.update fields

    wt
  end

end
