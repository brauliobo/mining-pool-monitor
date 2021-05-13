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
          send_report  if Time.now.min == 0
          @eth.process if Time.now.min.in? [0,20,40]
          sleep 1.minute
        end
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

    when /^\/read (\w+) (#{WRX})/
      puts "/read #{$1} #{$2}"
      data = @eth.pool_read $1, $2
      send_message msg, <<-EOS
#{Eth.url $1, $2}
*balance*: #{data.balance} ETH
*hashrate*: #{data.hashrate} MH/s
      EOS

    when /^\/report/
      send_report msg.chat.id

    when /^\/wallet_readings (#{WRX}) ?(\d*)/
      puts "/wallet_readings: #{$1} #{$2}"
      ds = DB[:wallets]
        .select(:pool, :read_at, :reported_hashrate.as(:MH), :balance)
        .where(wallet: $1)
        .order(Sequel.desc :read_at)
        .offset($2&.to_i)
        .limit(20)
      send_ds msg.chat.id, ds

    when /^\/pool_last_readings (#{WRX})/
      ds = DB[:balances]
        .where(pool: $1)
        .group(:pool, :wallet).having{ Sequel.function :max, :hours }
        .order(Sequel.desc(:hours))
        .limit(5)
      send_ds msg.chat.id, ds

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

  def send_report chat_id = ENV['REPORT_CHAT_ID'].to_i
    send_ds chat_id, DB[:pools]
  end

  def send_ds chat_id, ds, aliases: {}, &block
    text = "<pre>\n#{db_data ds, aliases: aliases, &block}\n</pre>"
    send_message SymMash.new(chat: {id: chat_id}), text, parse_mode: 'HTML'
  end

  def send_help msg
    help = <<-EOS
/*report*
/*read* <pool> <wallet>
/*#{e 'pool_last_readings'}* <pool>
/*#{e 'last_readings'}*
/*#{e 'wallet_readings'}* <wallet> <offset>
/*monitor* <pool> <wallet>
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
