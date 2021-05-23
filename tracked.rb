class Tracked

  def self.track data
    return unless data.hashrate > 0
    DB[:wallets_tracked].insert_conflict.insert(
      coin:          data.coin,
      pool:          data.pool,
      wallet:        data.wallet,
      hashrate_last: data.hashrate,
    )
  end

  def self.update_hashrate coin, pool, wallet, hashrate
    DB[:wallets_tracked]
      .where(coin: coin, pool: pool.to_s, wallet: wallet)
      .update(hashrate_last: hashrate, last_read_at: Time.now)
  end

end
