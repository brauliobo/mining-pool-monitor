class Bot
  module DbHelpers

    def db_data ds, aliases: {}, **params, &block
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
      send_message msg, text, parse_mode: 'HTML', **params
    end

  end
end
