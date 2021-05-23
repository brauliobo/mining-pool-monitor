require 'active_support/all'
require 'sequel'

DB = Sequel.connect adapter: 'postgres', database: 'mining_pools'

Sequel.split_symbols = true
Sequel.extension :core_extensions

DB.run File.read ARGV[0] if ARGV[0] and File.exists? ARGV[0]

