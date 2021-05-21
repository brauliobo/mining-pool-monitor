Sequel.migration do
  change do
    create_table(:intervals_defs) do
      Integer :period
      String :label, :text=>true
      Integer :seq
    end
    
    create_table(:wallets, :ignore_index_errors=>true) do
      String :coin, :text=>true
      String :pool, :text=>true
      String :wallet, :text=>true
      DateTime :read_at
      Float :reported_hashrate
      Float :balance
      
      index [:pool, :wallet, :balance, :read_at, :reported_hashrate], :name=>:wallets_all_index
    end
  end
end
