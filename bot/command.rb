class Bot
  class Command

    class InvalidCommand < StandardError; end

    include Report

    REGEXP = /^\/(\w+)\.?(\w+)? *(.*)/
    WRX    = /\w+.?\w*/
    LIST   = SymMash.new(
      start:  {},
      help:   {},
      exec:   {},
      update: {},

      report: {
        args: / ?(\w*)/,
      },
      read: {
        args: /([\w-]+) +(#{WRX})/,
        help: '<pool> <wallet>',
      },
      track: {
        args: /([\w-]+) +(#{WRX})/,
        help: '<pool> <wallet>',
      },
      pool_wallets: {
        args: /([\w-]+) *(\d*)/,
        help: '<pool> <offset> - List of tracked wallets',
      },
      pool_rewards: {
        args: /([\w-]+) *(\d*)/,
        help: -> { "<pool> <period=(#{DB[:intervals_defs].select_map(:period).join('|')})>" },
      },
      pool_readings: {
        args: /([\w-]+) *(\d*)/,
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

    attr_reader :bot, :msg, :cmd, :coin, :args

    delegate_missing_to :bot

    def initialize bot, msg, cmd, coin, args = ''
      @bot  = bot
      @cmd  = cmd
      @coin = bot.coins[coin]
      @msg  = msg
      @args = args
    end

    def run **params
      return unless dec = LIST[cmd.to_sym]

      if dec.args
        args = dec.args.match @args
        raise InvalidCommand unless args
        args = args.captures.map(&:presence)
        send "cmd_#{cmd}", *args, **params
      else
        send "cmd_#{cmd}", **params
      end

    rescue InvalidCommand
      send_message msg, "Incorrect format, usage is:\n#{mnfe help_cmd cmd}"
    rescue => e
      report_error msg, e
    end

    def cmd_start **params
      send_help msg
    end
    def cmd_help **params
      send_help msg
    end

    def cmd_update **params
      delete_message msg, msg.message_id, wait: 1.second
      return unless from_admin? msg
      update
    end

    def cmd_exec **params
      delete_message msg, msg.message_id, wait: 60.seconds
      return unless from_admin? msg
      ret = instance_eval(args).inspect
      send_message msg, ret, delete: 30, parse_mode: 'HTML'
    end

    def cmd_report order = nil, keep: nil, **params
      send_report msg, order, keep: keep
    end

    def cmd_read p, w, **params
      p.downcase!
      data    = coin.pool_read p, w
      data    = data.first if data.is_a? Array
      tracked = SymMash.new DB[:wallets_tracked].where(data.slice :coin, :pool, :wallet).first if data

      text = <<-EOS
#{me coin.class.url p, w}
*balance*: #{me data&.balance} #{coin.sym}
*hashrate*: #{me data&.hashrate} #{coin.hr_unit}
*tracking since*: #{me tracked&.started_at || Time.now}
*last read at*: #{me tracked&.last_read_at}
EOS
      send_message msg, text

      Tracked.track data rescue nil
    end

    def cmd_track p, w, **params
      cmd_read p, w
    end

    def cmd_pool_wallets p, off, **params
      ds = DB[:wallets_tracked]
        .select(*DB[:wallets_tracked].columns.excluding(:coin, :pool, :hashrate_avg_24h, :started_at)) # make it shorter
        .where(coin: coin.name, pool: p)
        .where{ hashrate_last > 0 }
        .order(Sequel.desc :last_read_at, nulls: :last)
        .limit(10)
        .offset(off&.to_i)
      send_ds msg, ds
    end

    def cmd_wallet_rewards w, off, **params
      ds = DB[:pairs_materialized]
        .select(*DB[:pairs_materialized].columns.excluding(:coin, :wallet, :period)) # make it shorter
        .where(Sequel.ilike :wallet, w)
        .order(:iseq, Sequel.asc(:pool))
        .offset(off&.to_i)
        .limit(10)
      send_ds msg, ds
    end

    def cmd_pool_rewards p, period, **params
      ds = DB[:rewards]
        .select(*DB[:rewards].columns.excluding(:pool)) # make it shorter
        .where(coin: coin.name, pool: p)
        .where(period: period&.to_i || 24)
        .order(:rew_mh_day)
      ds = array_middle ds.all
      send_ds msg, ds
    end

    def cmd_wallet_readings w, off, **params
      ds = DB[:wallet_reads]
        .select(:pool, :read_at, :hashrate.as(coin.hr_unit), :balance)
        .where(Sequel.ilike :wallet, w)
        .order(Sequel.desc(:read_at), Sequel.asc(:pool))
        .offset(off&.to_i)
        .limit(20)
      send_ds msg, ds
    end

    def cmd_pool_readings p, off, **params
      ds = DB[:wallet_reads]
        .select(:wallet, :read_at, :hashrate.as(coin.hr_unit), :balance)
        .where(coin: coin.name, pool: p)
        .order(Sequel.desc :read_at)
        .offset(off&.to_i)
        .limit(10)
      send_ds msg, ds
    end

    def cmd_exit msg, **params
      return unless from_admin? msg
      @exit = true
    end

    def array_middle a, limit = 20
      s = a.size/2 - limit/10
      s = 0 if s < 0
      e = a.size/2 + limit/2
      e = a.size-1 if e >= a.size
      a[s..e]
    end

  end
end
