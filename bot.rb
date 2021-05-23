require 'telegram/bot'
require 'tabulo'

class TelegramBot

  ADMIN_CHAT_ID = ENV['ADMIN_CHAT_ID'].to_i

  WRX = '0x\h+'

  def initialize token
    @eth   = Eth.new
    @token = token
  end

  def start
    Telegram::Bot::Client.run @token, logger: Logger.new(STDOUT) do |bot|
      @bot = bot

      Thread.new do
        loop do
          if Time.now.min == 0
            @eth.process
            DB.refresh_view :periods_materialized
            send_report SymMash.new chat: {id: ENV['REPORT_CHAT_ID'].to_i}
          end
          sleep 1.minute
        end
      rescue => e
        puts "error: #{e.message}\n#{e.backtrace.join("\n")}"
      end

      puts "bot: started, listening"
      @bot.listen do |msg|
        Thread.new do
          next unless msg.is_a? Telegram::Bot::Types::Message
          react msg
        end
        Thread.new{ sleep 1 and abort } if @exit # wait for other msg processing and trigger systemd restart
      end
    end
  end

  def react msg
    case text = msg.text
    when /^\/start/
      send_help msg
    when /^\/help/
      send_help msg

    when /^\/pool_wallets (\w+) ?(\d*)/
      puts "/wallet_rewards: #{$1}"
      ds = DB[:wallets_tracked]
        .select(*DB[:wallets_tracked].columns.excluding(:coin, :pool, :hashrate_avg_24h, :started_at)) # make it shorter
        .where(pool: $1)
        .order(Sequel.desc :last_read_at, nulls: :last)
        .limit(10)
        .offset($2.presence&.to_i)
      send_ds msg, ds

    when /^\/read (\w+) (#{WRX})/,
         /^\/track (\w+) (#{WRX})/
      puts "/read #{$1} #{$2}"
      data    = @eth.pool_read $1, $2
      tracked = SymMash.new DB[:wallets_tracked].where(data.slice :coin, :pool, :wallet).first if data

      send_message msg, <<-EOS
#{Eth.url $1, $2}
*balance*: #{data&.balance} ETH
*hashrate*: #{data&.hashrate} MH/s
*tracking since*: #{tracked&.started_at || Time.now}
*last read at*: #{tracked&.last_read_at}
EOS

      Tracked.track data rescue nil

    when /^\/report ?(\w*)/
      send_report msg, $1.presence

    when /^\/wallet_rewards (#{WRX})/
      puts "/wallet_rewards: #{$1}"
      ds = DB[:periods_materialized]
        .select(*DB[:periods_materialized].columns.excluding(:pool, :wallet, :period)) # make it shorter
        .where(Sequel.ilike :wallet, $1)
      send_ds msg, ds

    when /^\/pool_rewards (\w+) ?(\d*)/
      puts "/pool_rewards: #{$1} #{$2}"
      ds = DB[:rewards]
        .select(*DB[:rewards].columns.excluding(:pool)) # make it shorter
        .where(pool: $1)
        .where(period: $2.presence&.to_i || 24)
      send_ds msg, ds

    when /^\/wallet_readings (#{WRX}) ?(\d*)/
      puts "/wallet_readings: #{$1} #{$2}"
      ds = DB[:wallet_reads]
        .select(:pool, :read_at, :reported_hashrate.as(:MH), :balance)
        .where(Sequel.ilike :wallet, $1)
        .order(Sequel.desc :read_at)
        .offset($2.presence&.to_i)
        .limit(20)
      send_ds msg, ds

    when /^\/pool_readings (\w+) ?(\d*)/
      puts "/pool_readings: #{$1} #{$2}"
      ds = DB[:wallet_reads]
        .where(pool: $1)
        .order(Sequel.desc :read_at)
        .offset($2.presence&.to_i)
        .limit(5)
      send_ds msg, ds

    when /^\/monitor (\w+) (#{WRX})/i
      raise '/monitor: not implemented yet'

    when /echo/
      send_message msg, msg.inspect
    when /exit/
      return unless from_admin? msg
      @exit = true
    else
      puts "ignoring message: #{text}"
    end
  rescue => e
    send_message msg, "error: #{e e.message}"
    STDERR.puts "#{e.message}: #{e.backtrace.join "\n"}"
    raise
  end

  def from_admin? msg
    msg.from.id == ADMIN_CHAT_ID
  end

  def db_data ds, aliases: {}, &block
    data = ds.all
    return "no data returned" if data.blank?
    data = ds.map do |p|
      p = SymMash.new p
      block.call p if block
      p
    end
    Tabulo::Table.new data do |t|
      ds.first.keys.each do |k|
        t.add_column aliases[k] || k, &k
      end
    end.pack
  end

  def send_report msg, order = nil
    suffix  = "The scale is e-05, ETH rewarded/MH/24h. TW means the count of tracked wallets."
    suffix += "\nMultiple days periods are an average of sequential 1d periods."
    suffix += "\nIf you have a 100MH miner multiple it by 100."
    ds = DB[:pools]
    ds = ds.order Sequel.desc order.to_sym if order
    send_ds msg, ds, suffix: suffix
  end

  def send_ds msg, ds, prefix: nil, suffix: nil, **params, &block
    text = db_data ds, **params, &block
    text = "<pre>#{text}</pre>"
    text = "#{prefix}\n#{text}" if prefix
    text = "#{text}\n#{suffix}" if suffix
    send_message msg, text, parse_mode: 'HTML'
  end

  def send_help msg
    help = <<-EOS
/*report*
/*read* <pool> <wallet>
/*track* <pool> <wallet>
/*#{e 'pool_wallets'}* <pool> <offset> - List of tracked wallets
Commands for monitored wallets (first use /track above):
/*#{e 'wallet_rewards'}* <wallet>
/*#{e 'wallet_readings'}* <wallet> <offset>
/*#{e 'pool_rewards'}* <pool> <period=(24|72|144|216)>
/*#{e 'pool_readings'}* <pool> <offset>

Hourly reports at #{e 'https://t.me/mining_pools_monitor'}
EOS
    send_message msg, help
  end

  def send_message msg, text, parse_mode: 'MarkdownV2'
    @bot.api.send_message(
      reply_to_message: msg,
      chat_id:          msg.chat.id,
      text:             if parse_mode == 'MarkdownV2' then me text else text end,
      parse_mode:       parse_mode,
    )
  end

  MARKDOWN_RESERVED = %w[[ ] ( ) ~ ` > # + - = | { } . !]
  def me t
    MARKDOWN_RESERVED.each{ |c| t = t.gsub c, "\\#{c}" }
    t
  end
  def e t
    %w[* _].each{ |c| t = t.gsub c, "\\" + c }
    t
  end

end
