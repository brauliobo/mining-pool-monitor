class Tracked

  def self.track data
    update = {hashrate_last: :excluded__hashrate_last, last_read_at: :excluded__last_read_at}
    record = {
      coin:          data.coin,
      pool:          data.pool,
      wallet:        data.wallet,
      hashrate_last: data.hashrate,
      last_read_at:  Time.now,
    }

    DB[:wallets_tracked]
      .insert_conflict(constraint: :wallets_tracked_unique_constraint, update: update)
      .insert record
  end

end
