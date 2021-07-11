require 'telegram/bot'
require 'tabulo'

require_relative 'bot/report'
require_relative 'bot/commands'

Thread.report_on_exception = false

class TelegramBot

  ADMIN_CHAT_ID  = ENV['ADMIN_CHAT_ID'].to_i
  REPORT_CHAT_ID = ENV['REPORT_CHAT_ID'].to_i

  include Report
  include Commands

  def initialize token
    @eth   = Eth.new
    @token = token
  end

  def start
    Telegram::Bot::Client.run @token, logger: Logger.new(STDOUT) do |bot|
      @bot = bot

      puts "bot: started, listening"
      background_loop
      @bot.listen do |msg|
        Thread.new do
          next unless msg.is_a? Telegram::Bot::Types::Message
          react msg
        end
        Thread.new{ sleep 1 and abort } if @exit # wait for other msg processing and trigger systemd restart
      end
    end
  end

  def background_loop
    Thread.new do
      loop do
        if Time.now.min == 0
          @eth.process
          DB.refresh_view :periods_materialized
          send_report SymMash.new chat: {id: REPORT_CHAT_ID}
        end

        # sleep until next hour
        sleep 1 + ((DateTime.now.beginning_of_hour + 1.hour - DateTime.now)*1.day).to_i
      rescue => e
        puts "error: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end
  end

  def react msg
    cmd,args = msg.text.match(/^\/(\w+) *(.*)/)&.captures
    return unless cmd
    return unless cmd_def = CMD_LIST[cmd.to_sym]
    if cmd_def.args
      args = cmd_def.args.match(args)
      raise InvalidCommand unless args
      send "cmd_#{cmd}", msg, *args.captures.map(&:presence)
    else
      send "cmd_#{cmd}", msg
    end

  rescue InvalidCommand
    send_message msg, "Incorrect format, usage is:\n#{help_cmd cmd}"
  rescue => e
    error = e "msg: #{msg.inspect}\nerror: #{e.message} #{e.backtrace.join "\n"}"
    send_message SymMash.new(chat: {id: ADMIN_CHAT_ID}), error
    STDERR.puts "react error: #{error}"
  end

  def from_admin? msg
    msg.from.id == ADMIN_CHAT_ID
  end

  def db_data ds, aliases: {}, &block
    data = ds.to_a
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

  def send_ds msg, ds, prefix: nil, suffix: nil, **params, &block
    text = db_data ds, **params, &block
    text = "<pre>#{text}</pre>"
    text = "#{prefix}\n#{text}" if prefix
    text = "#{text}\n#{suffix}" if suffix
    send_message msg, text, parse_mode: 'HTML'
  end

  def help_cmd cmd
    help = CMD_LIST[cmd].help
    return unless help
    help = help.call if help.is_a? Proc
    "*/#{e cmd.to_s}* #{help}"
  end

  def send_help msg
    non_monitor = %i[read track]
    help = <<-EOS
#{non_monitor.map{ |c| help_cmd c }.join("\n")}
Commands for monitored wallets (first use /track above):
#{CMD_LIST.keys.excluding(*non_monitor).map{ |c| help_cmd c }.compact.join("\n")}

Hourly reports at #{e 'https://t.me/mining_pools_monitor'}
EOS
    send_message msg, help
  end

  def send_message msg, text, parse_mode: 'MarkdownV2'
    @bot.api.send_message(
      reply_to_message_id: msg.message_id,
      chat_id:             msg.chat.id,
      text:                if parse_mode == 'MarkdownV2' then me text else text end,
      parse_mode:          parse_mode,
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
