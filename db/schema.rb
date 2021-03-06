Sequel.migration do
  change do
    create_table(:coins) do
      String :coin, :size=>5, :null=>false
      Integer :multiplier
      
      primary_key [:coin]
    end
    
    create_table(:intervals_defs) do
      Integer :period
      String :label, :text=>true
      Integer :seq
    end
    
    create_table(:wallet_reads, :ignore_index_errors=>true) do
      String :coin, :text=>true
      String :pool, :text=>true
      String :wallet, :text=>true
      DateTime :read_at
      Float :hashrate
      Float :balance
      String :pair_24h
      
      index [:coin, :pool, :wallet, :read_at], :name=>:wallet_reads_unique_constraint, :unique=>true
    end
    
    create_table(:wallets_tracked, :ignore_index_errors=>true) do
      String :coin, :text=>true, :null=>false
      String :pool, :text=>true, :null=>false
      String :wallet, :text=>true, :null=>false
      Float :hashrate_last
      Float :hashrate_avg_24h
      DateTime :started_at, :default=>Sequel::CURRENT_TIMESTAMP
      DateTime :last_read_at
      
      primary_key [:coin, :pool, :wallet]
      
      index [:coin, :pool, :wallet, :hashrate_last, :hashrate_avg_24h], :name=>:wallets_tracked_all_index
      index [:coin, :pool, :wallet], :name=>:wallets_tracked_unique_constraint, :unique=>true
    end
  end
end
