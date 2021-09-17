require 'active_support/all'
require 'sequel'

DB = Sequel.connect adapter: 'postgres', database: 'mining_pools', max_connections: 5

Sequel.split_symbols = true
Sequel.extension :core_extensions

if ENV['DEBUG']
  DB.sql_log_level = :debug
  DB.loggers << Logger.new($stdout)
end

def db_run file
  DB.run File.read file if File.exists? file
end

db_run ARGV[0] if ARGV[0]

