require 'active_support/all'
require 'authem/railtie'
require 'authem/version'

module Authem
  autoload :Controller,         'authem/controller'
  autoload :Role,               'authem/role'
  autoload :Session,            'authem/session'
  autoload :Support,            'authem/support'
  autoload :Token,              'authem/token'
  autoload :User,               'authem/user'
  autoload :AmbigousRoleError,  'authem/errors/ambigous_role'
  autoload :UnknownRoleError,   'authem/errors/unknown_role'

  class << self
    attr_accessor :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end

  class Configuration
    attr_accessor :verify_client_auth_token

    def initialize
      @verify_client_auth_token = false
    end
  end
end
