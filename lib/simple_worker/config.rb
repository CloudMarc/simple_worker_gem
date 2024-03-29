module SimpleWorker


  # Config is used to setup the SimpleWorker client.
  # You must set the access_key and secret_key.
  #
  # config.global_attributes allows you to specify attributes that will automatically be set on every worker,
  #    this is good for database connection information or things that will be used across the board.
  #
  # config.database configures a database connection. If specified like ActiveRecord, SimpleWorker will automatically establish a connection
  # for you before running your worker.
  class Config
    attr_accessor :access_key,
                  :secret_key,
                  :host,
                  :global_attributes,
                  :models,
                  :mailers,
                  #:gems, # todo: move anything that uses this to merged_gems
                  :database,
                  :mailer,
                  :extra_requires,
                  #:auto_merge,
                  :server_gems,
                  :merged,
                  :unmerged,
                  :merged_gems,
                  :unmerged_gems


    def initialize
      @global_attributes = {}
      @extra_requires = []
      @merged = {}
      @unmerged = {}
      @merged_gems = {}
      @unmerged_gems = {}
      @mailers = {}

    end


    @gems_to_skip = ['actionmailer', 'actionpack', 'activemodel', 'activeresource', 'activesupport',
                     'bundler',
                     'mail',
                     'mysql2',
                     'rails',
                     'tzinfo' # HUGE!
    ]

    def self.gems_to_skip
      @gems_to_skip
    end

    def auto_merge=(b)
      if b
        SimpleWorker.logger.info "Initializing SimpleWorker for Rails 3..."
        start_time = Time.now
        SimpleWorker.configure do |c2|
          models_path = File.join(Rails.root, 'app/models/*.rb')
          models = Dir.glob(models_path)
          c2.models = models
          models.each { |model| c2.merge(model) }
          mailers_path = File.join(Rails.root, 'app/mailers/*.rb')
          Dir.glob(mailers_path).collect { |m| c2.mailers[File.basename(m)] = {:filename=>m, :name => File.basename(m), :path_to_templates=>File.join(Rails.root, "app/views/#{File.basename(m, File.extname(m))}")} }
          c2.extra_requires += ['active_support/core_ext', 'action_mailer']
          #puts 'DB FILE=' + File.join(Rails.root, 'config', 'database.yml').to_s
          if defined?(ActiveRecord) && File.exist?(File.join(Rails.root, 'config', 'database.yml'))
            c2.extra_requires += ['active_record']
            c2.database = Rails.configuration.database_configuration[Rails.env]
          else
            #puts 'NOT DOING ACTIVERECORD'
          end

          if defined?(ActionMailer) && ActionMailer::Base.smtp_settings
            c2.mailer = ActionMailer::Base.smtp_settings
          end
          c2.merged_gems.merge!(get_required_gems) if defined?(Bundler)
          SimpleWorker.logger.debug "MODELS " + c2.models.inspect
          SimpleWorker.logger.debug "MAILERS " + c2.mailers.inspect
          SimpleWorker.logger.debug "DATABASE " + c2.database.inspect
          #SimpleWorker.logger.debug "GEMS " + c2.gems.inspect
        end
        end_time = Time.now
        SimpleWorker.logger.info "SimpleWorker initialized. Duration: #{((end_time.to_f-start_time.to_f) * 1000.0).to_i} ms"
      end
    end


    def get_required_gems
      gems_in_gemfile = Bundler.environment.dependencies.select { |d| d.groups.include?(:default) }
      SimpleWorker.logger.debug 'gems in gemfile=' + gems_in_gemfile.inspect
      gems = {}
      specs = Bundler.load.specs
      SimpleWorker.logger.debug 'Bundler specs=' + specs.inspect
      SimpleWorker.logger.debug "gems_to_skip=" + self.class.gems_to_skip.inspect
      specs.each do |spec|
        SimpleWorker.logger.debug 'spec.name=' + spec.name.inspect
        SimpleWorker.logger.debug 'spec=' + spec.inspect
        if self.class.gems_to_skip.include?(spec.name)
          SimpleWorker.logger.debug "Skipping #{spec.name}"
          next
        end
#        next if dep.name=='rails' #monkey patch
        gem_info = {:name=>spec.name, :version=>spec.version}
        gem_info[:auto_merged] = true
        gem_info[:merge] = true
# Now find dependency in gemfile in case user set the require
        dep = gems_in_gemfile.find { |g| g.name == gem_info[:name] }
        if dep
          SimpleWorker.logger.debug 'dep found in gemfile: ' + dep.inspect
          SimpleWorker.logger.debug 'autorequire=' + dep.autorequire.inspect
          gem_info[:require] = dep.autorequire if dep.autorequire
#        spec = specs.find { |g| g.name==gem_info[:name] }
        end
        gem_info[:version] = spec.version.to_s
        gems[gem_info[:name]] = gem_info
        path = SimpleWorker::Service.get_gem_path(gem_info)
        if path
          gem_info[:path] = path
          if gem_info[:require].nil? && dep
            # see if we should try to require this in our worker
            require_path = gem_info[:path] + "/lib/#{gem_info[:name]}.rb"
            SimpleWorker.logger.debug "require_path=" + require_path
            if File.exists?(require_path)
              SimpleWorker.logger.debug "File exists for require"
              gem_info[:require] = gem_info[:name]
            else
              SimpleWorker.logger.debug "no require"
#              gem_info[:no_require] = true
            end
          end
        end
#        else
#          SimpleWorker.logger.warn "Could not find gem spec for #{gem_info[:name]}"
#          raise "Could not find gem spec for #{gem_info[:name]}"
#        end
      end
      gems
    end

    def get_server_gems
      return []
      # skipping this now, don't want any server dependencies if possible
      self.server_gems = SimpleWorker.service.get_server_gems unless self.server_gems
      self.server_gems
    end

    def get_atts_to_send
      config_data = {}
      config_data['access_key'] = access_key
      config_data['secret_key'] = secret_key
      config_data['database'] = self.database if self.database
      config_data['mailer'] = self.mailer if self.mailer
      config_data['global_attributes'] = self.global_attributes if self.global_attributes
      config_data['host'] = self.host if self.host
      config_data
    end

    def merge(file)
      f2 = SimpleWorker::MergeHelper.check_for_file(file, caller[2])
      fbase = f2[:basename]
      ret = f2
      @merged[fbase] = ret
      ret
    end

    def unmerge(file)
      f2 = SimpleWorker::MergeHelper.check_for_file(file, caller[2])
      fbase = f2[:basename]
      @unmerged[fbase] =f2
      @merged.delete(fbase)
    end

    # Merge a gem globally here
    def merge_gem(gem_name, options={})
      merged_gems[gem_name.to_s] = SimpleWorker::MergeHelper.create_gem_info(gem_name, options)
    end

    # Unmerge a global gem
    def unmerge_gem(gem_name)
      gs = gem_name.to_s
      gem_info = {:name=>gs}
      unmerged_gems[gs] = gem_info
      merged_gems.delete(gs)
    end

  end


  class MergeHelper

    # callerr is original file that is calling the merge function, ie: your worker.
    # See Base for examples.
    def self.check_for_file(f, callerr)
      SimpleWorker.logger.debug 'Checking for ' + f.to_s
      f = f.to_str
      f_ext = File.extname(f)
      if f_ext.empty?
        f_ext = ".rb"
        f << f_ext
      end
      exists = false
      if File.exist? f
        exists = true
      else
        # try relative
        #          p caller
        f2 = File.join(File.dirname(callerr), f)
        puts 'f2=' + f2
        if File.exist? f2
          exists = true
          f = f2
        end
      end
      unless exists
        raise "File not found: " + f
      end
      f = File.expand_path(f)
      require f if f_ext == '.rb'
      ret = {}
      ret[:path] = f
      ret[:extname] = f_ext
      ret[:basename] = File.basename(f)
      ret[:name] = ret[:basename]
      ret
    end

    def self.create_gem_info(gem_name, options={})
      gem_info = {:name=>gem_name, :merge=>true}
      if options.is_a?(Hash)
        gem_info.merge!(options)
        if options[:include_dirs]
          gem_info[:include_dirs] = options[:include_dirs].is_a?(Array) ? options[:include_dirs] : [options[:include_dirs]]
        end
      else
        gem_info[:version] = options
      end
      gem_info[:require] ||= gem_name

      path = SimpleWorker::Service.get_gem_path(gem_info)
      SimpleWorker.logger.debug "Gem path=#{path}"
      if !path
        raise "Gem path not found for #{gem_name}"
      end
      gem_info[:path] = path
      gem_info
    end
  end

end

