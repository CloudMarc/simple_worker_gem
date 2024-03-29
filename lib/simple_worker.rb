require_relative 'simple_worker/utils'
require_relative 'simple_worker/service'
require_relative 'simple_worker/base'
require_relative 'simple_worker/config'
require_relative 'simple_worker/used_in_worker'


module SimpleWorker
  @@logger = Logger.new(STDOUT)
  @@logger.level = Logger::INFO


  class << self
    attr_accessor :config,
                  :service

    def configure()
      yield(config)
      if config && config.access_key && config.secret_key
        SimpleWorker.service ||= Service.new(config.access_key, config.secret_key, :config=>config)
      end
    end

    def config
      @config ||= Config.new
    end

    def logger
      @@logger
    end

    def api_version
      3
    end
  end

end

if defined?(Rails)
#  puts 'Rails=' + Rails.inspect
#  puts 'vers=' + Rails::VERSION::MAJOR.inspect
  if Rails::VERSION::MAJOR == 2
    require_relative 'simple_worker/rails2_init.rb'
  else
    require_relative 'simple_worker/railtie'
  end
end
