class TelegramBot
  module Commands

    class InvalidCommand < StandardError; end

    WRX = /\w+.?\w*/

    CMD_LIST = SymMash.new(
      start:  {},
      help:   {},
      report: {
        args: / ?(\w*)/,
      },
      read: {
        args: /(\w+) +(#{WRX})/,
        help: '<pool> <wallet>',
      },
      track: {
        args: /(\w+) +(#{WRX})/,
        help: '<pool> <wallet>',
      },
      pool_wallets: {
        args: /(\w+) *(\d*)/,
        help: '<pool> <offset> - List of tracked wallets',
      },
      pool_rewards: {
        args: /(\w+) *(\d*)/,
        help: -> { "<pool> <period=(#{DB[:intervals_defs].select_map(:period).join('|')})>" },
      },
      pool_readings: {
        args: /(\w+) *(\d*)/,
        help: '<pool> <offset>',
      },
      wallet_rewards: {
        args: /(#{WRX}) *(\d*)/,
        help: '<wallet>',
      },
      wallet_readings: {
        args: /(#{WRX}) *(\d*)/,
        help: '<wallet>',
      },
    )

    def cmd_start msg
      send_help msg
    end

    def cmd_help msg
      send_help msg
    end

    def cmd_report msg, order = nil
      send_report msg, order
    end

    def cmd_read msg, p, w
      data    = @eth.pool_read p, w
      data    = data.first if data.is_a? Array
      tracked = SymMash.new DB[:wallets_tracked].where(data.slice :coin, :pool, :wallet).first if data

      send_message msg, <<-EOS
#{e Eth.url p, w}
*balance*: #{data&.balance} ETH
*hashrate*: #{data&.hashrate} MH/s
*tracking since*: #{tracked&.started_at || Time.now}
*last read at*: #{tracked&.last_read_at}
EOS

      Tracked.track data rescue nil
    end

    def cmd_track msg, p, w
      cmd_read msg, p, w
    end

    def cmd_pool_wallets msg, p, off
      ds = DB[:wallets_tracked]
        .select(*DB[:wallets_tracked].columns.excluding(:coin, :pool, :hashrate_avg_24h, :started_at)) # make it shorter
        .where(pool: p)
        .order(Sequel.desc :last_read_at, nulls: :last)
        .limit(10)
        .offset(off&.to_i)
      send_ds msg, ds
    end

    def cmd_wallet_rewards msg, w, off
      ds = DB[:periods_materialized]
        .select(*DB[:periods_materialized].columns.excluding(:pool, :wallet, :period)) # make it shorter
        .where(Sequel.ilike :wallet, w)
        .offset(off&.to_i)
      send_ds msg, ds
    end

    def cmd_pool_rewards msg, p, period
      ds = DB[:rewards]
        .select(*DB[:rewards].columns.excluding(:pool)) # make it shorter
        .where(pool: p)
        .where(period: period&.to_i || 24)
      send_ds msg, ds
    end

    def cmd_wallet_readings msg, w, off
      ds = DB[:wallet_reads]
        .select(:pool, :read_at, :reported_hashrate.as(:MH), :balance)
        .where(Sequel.ilike :wallet, w)
        .order(Sequel.desc :read_at)
        .offset(off&.to_i)
        .limit(20)
      send_ds msg, ds
    end

    def cmd_pool_readings msg, p, off
      ds = DB[:wallet_reads]
        .where(pool: p)
        .order(Sequel.desc :read_at)
        .offset(off&.to_i)
        .limit(5)
      send_ds msg, ds
    end

    def cmd_exit msg
      return unless from_admin? msg
      @exit = true
    end

  end
end
