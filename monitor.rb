require 'bundler/setup'
require 'active_support/all'
require 'dotenv'
require 'hashie'
require 'mechanize'
Dotenv.load! '.env'

require_relative 'exts/sym_mash'
require_relative 'exts/peach'

require_relative 'db'
require_relative 'eth'
require_relative 'bot'
require_relative 'tracked'

