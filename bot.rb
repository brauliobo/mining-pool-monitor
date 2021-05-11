require 'telegram/bot'
require 'tabulo'

class TelegramBot

  def initialize token
    @eth   = Eth.new
    @token = token
  end

  def start
    Telegram::Bot::Client.run @token, logger: Logger.new(STDOUT) do |bot|
      @bot = bot

      Thread.new do
        loop do
          send_report     if Time.now.min == 0
          Eth.new.process if Time.now.min.in? [0,20,40]
          sleep 1.minute
        end
      end

      puts "bot: started, listening"
      @bot.listen do |msg|
        Thread.new do
          react msg
        end
        Thread.new{ sleep 1 and abort } if @exit # wait for other msg processing and trigger systemd restart
      end
    end
  end

  def react msg
    case msg
    when Telegram::Bot::Types::Message
      case text = msg.text
      when /^\/start/
        send_help msg
      when /^\/help/
        send_help msg

      when /^\/read (\w+) (0x\w+)/
        data = @eth.pool_read $1, $2
        send_message msg, <<-EOS
*#{$1}* *#{$2}*
*balance*: #{data.balance} ETH
*hashrate*: #{data.hashrate} MH/s
EOS

      when /^\/report/
        send_report msg.chat.id

      when /^\/pool_last_readings (\w+)/
        ds = DB[:balances]
          .where(pool: $1)
          .where{ hours > 6 }
          .group(:pool, :wallet).having{ Sequel.function :max, :hours }
          .limit(5)
        send_ds msg.chat.id, ds

      when /^\/monitor (\w+) (0x\w+)/i
        raise 'not implemented yet'

      when /echo/
        send_message msg, msg.inspect
      when /exit/
        return unless msg.from.id
        @exit = true
      else
        puts "ignoring message: #{text}"
      end
    end
  rescue => e
    send_message msg, "error: #{e e.message}"
    STDERR.puts "#{e.message}: #{e.backtrace.join "\n"}"
    raise
  end

  def db_data ds
    data = ds.all.map{ |p| SymMash.new p }
    Tabulo::Table.new(data, *data.first.keys).pack
  end

  def send_report chat_id = ENV['REPORT_CHAT_ID'].to_i
    send_ds chat_id, DB[:pools]
  end

  def send_ds chat_id, ds
    text = "<pre>#{db_data ds}</pre>"
    @bot.api.send_message(
      chat_id:    chat_id,
      text:       text,
      parse_mode: 'HTML',
    )
  end

  def send_help msg
    help = <<-EOS
/*report*
/*read* <pool> <wallet>
/*#{e 'pool_last_readings'}* <pool>
/*#{e 'last_readings'}*
/*monitor* <pool> <wallet>
EOS
    send_message msg, help
  end

  def send_message msg, text
    @bot.api.send_message(
      reply_to_message: msg,
      chat_id:          msg.chat.id,
      text:             me(text),
      parse_mode:       'MarkdownV2',
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
