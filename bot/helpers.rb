require_relative 'db_helpers'

class TelegramBot
  module Helpers

    include DbHelpers

    ADMIN_CHAT_ID  = ENV['ADMIN_CHAT_ID'].to_i
    REPORT_CHAT_ID = ENV['REPORT_CHAT_ID'].to_i

    def from_admin? msg
      msg.from.id == ADMIN_CHAT_ID
    end

    def edit_message msg, id, text: nil, type: 'text', **params
      bot.api.send "edit_message_#{type}",
        chat_id: msg.chat.id, message_id: id, text: text, **params

    rescue ::Telegram::Bot::Exceptions::ResponseError => e
      resp = SymMash.new JSON.parse e.response.body
      return if resp.description.match(/exactly the same as a current content/)
      raise
    end

    def help_cmd cmd
      help = Command::LIST[cmd].help
      return unless help
      help = help.call if help.is_a? Proc
      "*/#{e cmd.to_s}* #{help}"
    end

    def send_message msg, text, type: 'message', parse_mode: 'MarkdownV2', delete: nil, **params
      text = if parse_mode == 'MarkdownV2' then me text elsif parse_mode == 'HTML' then text else text end
      text = text.first 4090
      resp = SymMash.new @bot.api.send "send_#{type}",
        reply_to_message_id: msg.message_id,
        chat_id:             msg.chat.id,
        text:                text,
        parse_mode:          'HTML',
        **params
      delete_message msg, resp.result.message_id, wait: delete if delete
      resp
    end

    def delete_message msg, id, wait: 30.seconds
      Thread.new do
        sleep wait
      ensure
        api.delete_message chat_id: msg.chat.id, message_id: id
      end
    end

    def report_error msg, e
      return unless msg
      msg_ct = if msg.respond_to? :text then msg.text else msg.data end
      error  = "msg: #{he msg_ct}"
      error << "\nerror: <pre>#{he e.message}\n"
      error << "#{he e.backtrace.join "\n"}</pre>"
      send_message msg, error, parse_mode: 'HTML', delete: 30.seconds
    end

    def api
      bot.api
    end

    MARKDOWN_RESERVED = %w[# [ ] ( ) ~ ` > # + - = | { } . !]
    def me t
      MARKDOWN_RESERVED.each{ |c| t = t.gsub c, "\\#{c}" }
      t
    end
    def he t
      return if t.blank?
      CGI::escapeHTML t
    end
    def e t
      %w[* _].each{ |c| t = t.gsub c, "\\" + c }
      t
    end

  end
end
