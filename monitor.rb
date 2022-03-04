require 'bundler/setup'
require 'active_support/all'
require 'dotenv'
require 'hashie'
require 'mechanize'
Dotenv.load! '.env'

require_relative 'exts/sym_mash'
require_relative 'exts/peach'

require_relative 'db'
require_relative 'models/wallet_tracked'

require_relative 'coin/base'
require_relative 'coin/eth'
require_relative 'coin/etc'
require_relative 'coin/rvn'
require_relative 'coin/ergo'
require_relative 'coin/chia'

require_relative 'bot'
require_relative 'tracked'

