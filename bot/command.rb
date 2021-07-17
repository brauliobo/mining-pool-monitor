class TelegramBot
  class Command

    class InvalidCommand < StandardError; end

    include Report

    REGEXP = /^\/(\w+)\.?(\w+)? *(.*)/
    WRX    = /\w+.?\w*/
    LIST   = SymMash.new(
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

    attr_reader :bot, :msg, :cmd, :coin, :args

    def initialize bot, msg, cmd, coin, args = ''
      @bot  = bot
      @cmd  = cmd
      @coin = bot.coins[coin]
      @msg  = msg
      @args = args
    end

    def run
      return unless dec = LIST[cmd.to_sym]

      if dec.args
        args = dec.args.match @args
        raise InvalidCommand unless args
        args = args.captures.map(&:presence)
        send "cmd_#{cmd}", *args
      else
        send "cmd_#{cmd}"
      end

    rescue InvalidCommand
      send_message msg, "Incorrect format, usage is:\n#{help_cmd cmd}"
    rescue => e
      error = e "msg: #{msg.inspect}\nerror: #{e.message} #{e.backtrace.join "\n"}"
      send_message SymMash.new(chat: {id: bot.class::ADMIN_CHAT_ID}), error
      STDERR.puts "error: #{error}"
    end

    def cmd_start
      send_help msg
    end

    def cmd_help
      send_help msg
    end

    def cmd_report order = nil
      send_report msg, order
    end

    def cmd_read p, w
      data    = coin.pool_read p, w
      data    = data.first if data.is_a? Array
      tracked = SymMash.new DB[:wallets_tracked].where(data.slice :coin, :pool, :wallet).first if data

      send_message msg, <<-EOS
#{e Coin::Eth.url p, w}
*balance*: #{data&.balance} #{coin.sym}
*hashrate*: #{data&.hashrate} #{coin.hr_unit}
*tracking since*: #{tracked&.started_at || Time.now}
*last read at*: #{tracked&.last_read_at}
EOS

      Tracked.track data rescue nil
    end

    def cmd_track p, w
      cmd_read p, w
    end

    def cmd_pool_wallets p, off
      ds = DB[:wallets_tracked]
        .select(*DB[:wallets_tracked].columns.excluding(:coin, :pool, :hashrate_avg_24h, :started_at)) # make it shorter
        .where(coin: coin.name, pool: p)
        .where{ hashrate_last > 0 }
        .order(Sequel.desc :last_read_at, nulls: :last)
        .limit(10)
        .offset(off&.to_i)
      send_ds msg, ds
    end

    def cmd_wallet_rewards w, off
      ds = DB[:periods_materialized]
        .select(*DB[:periods_materialized].columns.excluding(:coin, :wallet, :period)) # make it shorter
        .where(Sequel.ilike :wallet, w)
        .order(:iseq)
        .offset(off&.to_i)
        .limit(10)
      send_ds msg, ds
    end

    def cmd_pool_rewards p, period
      ds = DB[:rewards]
        .select(*DB[:rewards].columns.excluding(:pool)) # make it shorter
        .where(coin: coin.name, pool: p)
        .where(period: period&.to_i || 24)
        .order(:eth_mh_day)
      ds = array_middle ds.all
      send_ds msg, ds
    end

    def cmd_wallet_readings w, off
      ds = DB[:wallet_reads]
        .select(:pool, :read_at, :hashrate.as(coin.hr_unit), :balance)
        .where(Sequel.ilike :wallet, w)
        .order(Sequel.desc :read_at)
        .offset(off&.to_i)
        .limit(20)
      send_ds msg, ds
    end

    def cmd_pool_readings p, off
      ds = DB[:wallet_reads]
        .where(coin: coin.name, pool: p)
        .order(Sequel.desc :read_at)
        .offset(off&.to_i)
        .limit(5)
      send_ds msg, ds
    end

    def cmd_exit msg
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

    def method_missing method, *args, &block
      bot.send method, *args, &block
    end

  end
end
