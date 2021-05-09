require 'sequel'

DB = Sequel.sqlite 'pools.db'

DB.create_table :wallets do
  String :coin
  String :pool
  String :wallet
  Time :reference_time
  Time :read_at
  Float :reported_hashrate
  Float :balance

  index [:coin, :pool, :wallet]
end unless :wallets.in? DB.tables

DB.run File.read 'views.sql'

