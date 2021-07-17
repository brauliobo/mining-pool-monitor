class TelegramBot
  module Report

    REPORT_DEFAULT_ORDER = '3w'

    def send_report msg, order = nil
      order ||= REPORT_DEFAULT_ORDER
      suffix  = "Scale: #{coin.scale} #{coin.sym} rewarded/#{coin.hr_unit}/24h. TW: count of tracked wallets"
      suffix += "\nOrder: highest #{order} rewards."
      suffix += "\nMultiple days periods are the median of multiple 24h rewards."
      ds = report_data order
      send_ds msg, ds, suffix: suffix
    end

    def report_data order = nil
      ds = DB[:rewards]
        .group(:pool)
        .select(:pool)
        .select_append{ count(distinct wallet).as :TW }
        .where(coin: coin.name)

      DB[:intervals_defs].map{ |id| SymMash.new id }.each do |id|
        cond = Sequel.case [[{period: id.period}, :eth_mh_day]], nil
        #ds = ds.select_append{ round(avg(cond), 2).as id.label }
        ds = ds.select_append{ round(Sequel.cast(percentile_cont(0.5).within_group(cond), :numeric), 2).as id.label }
      end

      data = ds.all.map{ |d| SymMash.new d }
      oc   = order.to_sym if order
      oc   = REPORT_DEFAULT_ORDER unless oc.in? data.first.keys
      data = data.sort{ |a,b| if a[oc] && b[oc] then b[oc] <=> a[oc] elsif a[oc] then -1 else 1 end }
      data.each.with_index do |d, i|
        d.pool = "#{i+1}. #{d.pool}"
      end

      data
    end

  end
end
