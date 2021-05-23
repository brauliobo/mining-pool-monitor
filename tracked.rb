class Tracked

  def self.track data
    update = {hashrate_last: :excluded__hashrate_last, last_read_at: :excluded__last_read_at}
    record = SymMash.new(
      coin:          data.coin,
      pool:          data.pool,
      wallet:        data.wallet,
      hashrate_last: data.hashrate,
    )
    record.last_read_at = data.read_at || Time.now if data.hashrate > 0

    DB[:wallets_tracked]
      .insert_conflict(constraint: :wallets_tracked_unique_constraint, update: update)
      .insert record
  end

end
