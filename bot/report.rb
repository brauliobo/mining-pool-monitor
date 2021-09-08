class Bot
  module Report

    REPORT_DEFAULT_ORDER = '1m'

    def send_report msg, order = nil, keep: nil
      suffix  = "Scale: #{coin.scale} #{coin.sym} rewarded/#{coin.hr_unit}/24h."
      suffix += "\nTW: count of tracked wallets."

      ds = DB[:rewards]
        .group(:pool)
        .select(:pool)
        .select_append{ count(distinct wallet).as :TW }
        .where(coin: coin.name)
      DB[:intervals_defs].map{ |id| SymMash.new id }.each do |id|
        cond = Sequel.case [[{period: id.period}, :eth_mh_day]], nil
        ds = ds.select_append{ round(avg(cond), 2).as id.label }
      end
      data = ds.all.map{ |d| SymMash.new d }
      return if data.blank?

      oc   = order || REPORT_DEFAULT_ORDER
      oc   = oc.to_sym
      oc   = REPORT_DEFAULT_ORDER unless oc.in? data.first.keys
      data = data.sort{ |a,b| if a[oc] && b[oc] then b[oc] <=> a[oc] elsif a[oc] then -1 else 1 end }
      data.each.with_index do |d, i|
        d.pool = "#{i+1}. #{d.pool}"
      end

      if report_group? msg
        delete = 3.minutes if !keep
        delete = 1.hour    if  keep and Time.now.hour % 3 > 0
      end

      aliases = {pool: "#{coin.name} pool", oc => "▼#{oc}"}
      send_ds msg, data, suffix: suffix, delete_both: delete, aliases: aliases
    end

  end
end
