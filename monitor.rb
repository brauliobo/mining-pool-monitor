require 'bundler/setup'
require 'active_support/all'
require 'dotenv'
require 'hashie'
require 'mechanize'
Dotenv.load! '.env'

require_relative 'db'
require_relative 'eth'

