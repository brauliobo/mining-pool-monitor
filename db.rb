require 'active_support/all'
require 'sequel'

DB = Sequel.connect adapter: 'postgres', database: 'mining_pools'

Sequel.extension :core_extensions

DB.create_table :wallets do
  String :coin
  String :pool
  String :wallet
  Time :read_at
  Float :reported_hashrate
  Float :balance

  index [:coin, :pool, :wallet]
end unless :wallets.in? DB.tables

DB.run File.read ARGV[0] if ARGV[0] and File.exists? ARGV[0]

