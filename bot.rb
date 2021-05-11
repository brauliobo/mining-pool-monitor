require 'telegram/bot'
require 'tabulo'

class TelegramBot

  def initialize token
    @eth   = Eth.new
    @token = token
  end

  def start
    Telegram::Bot::Client.run @token, logger: Logger.new(STDOUT) do |bot|
      puts "bot: started, listening"
      @bot = bot
      @bot.listen do |msg|
        abort if @exit # trigger systemd restart
        Thread.new do
          react msg
        end
      end

      Thread.new do
        loop do
          Eth.new.process
          sleep 29.minutes
        end
      end

      Thread.new do
        loop do
          send_report
          sleep 1.hour
        end
      end
    end
  end

  def react msg
    case msg
    when Telegram::Bot::Types::Message
      case text = msg.text
      when /^\/start/
        send_help msg

      when /^\/read (\w+) (0x\w+)/
        data = @eth.pool_read $1, $2
        send_message msg, <<-EOS
pool *#{$1}*, wallet *#{$2}*
*balance*: #{data.balance}
*hashrate*: #{data.hashrate}
EOS

      when /^\/report/
        send_report msg.chat.id

      when /^\/monitor (\w+) (0x\w+)/i

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

  def send_report chat_id = ENV['REPORT_CHAT_ID']
    data = DB[:pools].all.map{ |p| SymMash.new p }
    text = Tabulo::Table.new(data, *data.first.keys).pack
    text = "<pre>#{text}</pre>"
    @bot.api.send_message(
      chat_id:    chat_id,
      text:       text,
      parse_mode: 'HTML',
    )
  end

  def send_help msg
    help = <<-EOS
/report
/#{e 'last_readings'}
/read <pool> <wallet>
/monitor <pool> <wallet>
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
