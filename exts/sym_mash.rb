class SymMash < ::Hashie::Mash

  disable_warnings

  include Hashie::Extensions::Mash::SymbolizeKeys

end
