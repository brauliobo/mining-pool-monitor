require 'telegram/bot'
require 'tdlib-ruby'
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

  class_attribute :token
  class_attribute :pm_token
  self.token    = ENV['TOKEN']
  self.pm_token = ENV['PM_TOKEN']

  self.bot_name = 'mining-pools-bot'

  TD.configure do |config| 
    config.client.api_id = ENV['TDLIB_API_ID']
    config.client.api_hash = ENV['TDLIB_API_HASH']
  end
  TD::Api.set_log_verbosity_level 0
  class_attribute :td
  self.td = TD::Client.new

  def initialize
    @coins = Coin::Base.instances
  end

  def start
    wait_net_up
    Telegram::Bot::Client.run token, logger: Logger.new(STDOUT) do |bot|
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

  def update
    coins.api_peach{ |_, c| c.process }
    db_run 'db/update.sql'
    msg = fake_msg REPORT_CHAT_ID
    coins.api_peach do |coin, c|
      Command.new(self, msg, :report, coin).run keep: true
    end
  end

  def background_loop
    Thread.new do
      loop do
        update if Time.now.min == 0

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
Coins supported:
*#{coins.keys.join " "}*

#{non_monitor.map{ |c| help_cmd c }.join("\n")}
Commands for monitored wallets (first use /track above):
#{Command::LIST.keys.excluding(*non_monitor).map{ |c| help_cmd c }.compact.join("\n")}

Hourly reports at #{'https://t.me/mining_pools_monitor'}
EOS
    send_message msg, mnfe(help)
  end

  def help_cmd cmd
    help = Command::LIST[cmd].help
    return unless help
    help = help.call if help.is_a? Proc
    "*/#{me cmd.to_s}.<coin>* #{help}"
  end

end
