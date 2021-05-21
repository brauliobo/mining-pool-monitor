require 'active_support/all'
require 'sequel'

DB = Sequel.connect adapter: 'postgres', database: 'mining_pools'

Sequel.extension :core_extensions

DB.run File.read ARGV[0] if ARGV[0] and File.exists? ARGV[0]

