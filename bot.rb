require 'telegram/bot'
require 'tabulo'

require_relative 'bot/report'
require_relative 'bot/command'
require_relative 'bot/helpers'
require_relative 'bot/db_helpers'

Thread.report_on_exception = false

class Bot

  attr_reader :bot

  include Helpers
  include DbHelpers

  DEFAULT_COIN = :eth
  attr_reader :coins

  def initialize token
    @coins = Coin::Base.instances
    @token = token
  end

  def start
    Telegram::Bot::Client.run @token, logger: Logger.new(STDOUT) do |bot|
      @bot = bot

      puts 'bot: started, listening'
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
          coins.api_peach{ |_, c| c.process }
          DB.refresh_view :periods_materialized
          msg = fake_msg REPORT_CHAT_ID
          Command.new(self, msg, :report, DEFAULT_COIN).run
        end

        # sleep until next hour
        sleep 1 + ((DateTime.now.beginning_of_hour + 1.hour - DateTime.now)*1.day).to_i
      rescue => e
        puts "error: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end
  end

  def react msg
    cmd,coin,args = msg.text.match(Command::REGEXP)&.captures
    return unless cmd
    cmd,coin = coin,cmd if coin and Command::LIST[coin]
    coin ||= DEFAULT_COIN

    cmd = Command.new self, msg, cmd, coin, args
    cmd.run
  end

  def send_help msg
    non_monitor = %i[read track]
    help = <<-EOS
#{non_monitor.map{ |c| help_cmd c }.join("\n")}
Commands for monitored wallets (first use /track above):
#{Command::LIST.keys.excluding(*non_monitor).map{ |c| help_cmd c }.compact.join("\n")}

Hourly reports at #{e 'https://t.me/mining_pools_monitor'}
EOS
    send_message msg, help
  end

end
