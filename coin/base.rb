module Coin
  class Base

    class_attribute :instances
    self.instances = SymMash.new

    class_attribute :pools
    self.pools = nil

    class_attribute :hr_unit
    self.hr_unit = 'MH/s'

    def self.name
      @name ||= super.demodulize.underscore
    end
    def name
      @name ||= self.class.name
    end

    class_attribute :sym

    def self.url pool, wallet
      self.pools[pool].url % {w: wallet}
    end

    def self.inherited subclass
      inst = subclass.new
      instances[inst.name] = inst
    end

    attr_reader :record

    def initialize
      @record = SymMash.new DB[:coins].first coin: name
    end

    delegate :multiplier, to: :record

    def scale
      "e-#{multiplier.to_s.count '0'}"
    end

    def get url, params
      url  = url % params
      puts "GET #{url}" if ENV['DEBUG']
      data = http.get url
      data = JSON.parse data.body
      data = SymMash.new data if data.is_a? Hash
      data = data.map{ |d| SymMash.new d } if data.is_a? Array
      data
    rescue => e
      puts "error #{name}/#{url}: #{e.message}"
    end

    def high_mh_deviation? v1, v2
      (v1/v2 - 1).abs > 1
    end

    def pool_read pool, wallet
      input = self.pools[pool].merge wallet: wallet
      data  = if input.read.is_a? Symbol then method(input.read).call input else instance_exec input, &input.read end

      adata = if data.is_a? Array then data else [data] end
      adata.each do |d|
        return puts "#{name}/#{pool}/#{wallet}: discarding deviating hashrate" if d.current_hashrate and high_mh_deviation? d.current_hashrate, d.hashrate

        # due to conflicting worker name in multiple miners, reported can be lower
        d.hashrate = d.average_hashrate if d.average_hashrate and high_mh_deviation? d.average_hashrate, d.hashrate

        d.coin      = self.name
        d.pool      = pool.to_s
        d.wallet    = wallet
        d.read_at ||= Time.now
      end
      Tracked.track adata.first

      data
    rescue => e
      puts "#{name}/#{pool}/#{wallet}: #{e.message}"
    end

    def pool_fetch pool
      wallets(pool).api_peach.map do |w|
        data  = pool_read pool, w rescue nil
        next puts "#{name}/#{pool}: no data for #{w}" unless data
        puts "#{name}/#{pool}: #{data.inspect}"

        data
      end.compact
    end

    def process
      self.pools.cpu_peach do |pool, opts|
        pool_process pool, opts
      end
    end

    def pool_process pool, opts = self.pools[pool]
      data = pool_fetch pool
      return if ENV['DRY']
      data = data.flat_map{ |d| opts.db_parse.call d } if opts.db_parse
      data = data.flat_map{ |d| d.slice(*DB[:wallet_reads].columns) }
      DB[:wallet_reads].insert_conflict.multi_insert data
    end

    def wallets pool
      ds = DB[:wallets_tracked].where(coin: self.name, pool: pool.to_s)
      ds = ds.where{ (hashrate_last > 0) & (last_read_at >= 24.hours.ago) } unless ENV['RESCRAPE']
      ds.select_map(:wallet)
    end

    def http
      @http ||= Mechanize.new do |agent|
        agent.open_timeout = 15
        agent.read_timeout = 15
      end
    end

  end
end
