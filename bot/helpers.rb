class Bot
  module Helpers

    extend ActiveSupport::Concern
    included do
      class_attribute :error_delete_time
      self.error_delete_time = 30.seconds

      def self.mock
        define_method :send_message do |msg, text, *args|
          puts text
          SymMash.new result: {message_id: 1}, text: text
        end
        define_method :edit_message do |msg, id, text: nil, **params|
          puts text
        end
        define_method :delete_message do |msg, id, text: nil, **params|
          puts "deleting #{id}"
        end
      end
    end

    ADMIN_CHAT_ID  = ENV['ADMIN_CHAT_ID']&.to_i
    REPORT_CHAT_ID = ENV['REPORT_CHAT_ID']&.to_i

    def net_up?
      Net::HTTP.new('www.google.com').head('/').kind_of? Net::HTTPOK
    end
    def wait_net_up
      sleep 1 while !net_up?
    end

    def from_admin? msg
      msg.from.id == ADMIN_CHAT_ID
    end
    def report_group? msg
      msg.chat.id == REPORT_CHAT_ID
    end
    def in_group? msg
      msg.from.id == msg.chat.id
    end

    def edit_message msg, id, text: nil, type: 'text', parse_mode: 'MarkdownV2', **params
      text = parse_text text, parse_mode: parse_mode
      api.send "edit_message_#{type}",
        chat_id:    msg.chat.id,
        message_id: id,
        text:       text,
        caption:    text,
        parse_mode: parse_mode,
        **params

    rescue ::Telegram::Bot::Exceptions::ResponseError => e
      resp = SymMash.new JSON.parse e.response.body
      return if resp.description.match(/exactly the same as a current content/)
      raise
    end

    def send_message msg, text, type: 'message', parse_mode: 'MarkdownV2', delete: nil, delete_both: nil, **params
      _text = text
      text  = parse_text text, parse_mode: parse_mode
      resp  = SymMash.new api.send "send_#{type}",
        reply_to_message_id: msg.message_id,
        chat_id:             msg.chat.id,
        text:                text,
        caption:             text,
        parse_mode:          parse_mode,
        **params
      resp.text = _text

      delete = delete_both if delete_both
      delete_message msg, resp.result.message_id, wait: delete if delete
      delete_message msg, msg.message_id, wait: delete_both if delete_both

      resp
    rescue => e
      binding.pry if ENV['PRY_SEND_MESSAGE']
      raise
    end

    def delete_message msg, id, wait: 30.seconds
      Thread.new do
        sleep wait if wait
      ensure
        api.delete_message chat_id: msg.chat.id, message_id: id
      end
    end

    def report_error msg, e, context: nil
      return unless msg
      msg_ct = if msg.respond_to? :text then msg.text else msg.data end
      error  = "<b>msg</b>: #{he msg_ct}"
      error << "\n\n<b>context</b>: #{he context}" if context
      error << "\n\n<b>error</b>: <pre>#{he e.message}\n"
      error << "#{he e.backtrace.join "\n"}</pre>"

      STDERR.puts "error: #{error}"
      send_message msg, error, parse_mode: 'HTML', delete_both: error_delete_time
      send_message admin_msg, error, parse_mode: 'HTML' if ADMIN_CHAT_ID != msg.chat.id
    end

    def fake_msg chat_id
      SymMash.new chat: {id: chat_id}
    end
    def admin_msg
      fake_msg ADMIN_CHAT_ID
    end

    def api
      bot.api
    end

    def parse_text text, parse_mode:
      return unless text
      text = if parse_mode == 'MarkdownV2' then me text elsif parse_mode == 'HTML' then text else text end
      text = text.first 4090 if text.size > 4096
      text
    end

    MARKDOWN_RESERVED = %w[\# [ ] ( ) ~ # + - = | { } . ! < >]
    MARKDOWN_FORMAT   = %w[* _ `]
    def me t
      MARKDOWN_RESERVED.each{ |c| t = t.gsub c, "\\#{c}" }
      t
    end
    def e t
      MARKDOWN_FORMAT.each{ |c| t = t.gsub c, "\\#{c}" }
      t
    end

    def he t
      return if t.blank?
      CGI::escapeHTML t
    end

  end
end
