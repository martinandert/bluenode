module Bluenode
  class NativeModule
    FILES = Dir[File.expand_path(File.join('..', 'shims', '*.js'), __FILE__)].freeze

    SOURCES = FILES.inject({}) do |memo, filename|
      id = File.basename(filename, '.js')
      fn = lambda { File.read(filename )}

      memo.merge! id => fn
    end.freeze

    NAMES = SOURCES.keys.freeze

    class << self
      def require(context, id)
        return self if id == 'native_module'

        cached = cache[id]

        return cached.exports if cached

        raise LoadError, "no such native module #{id}" unless exist?(id)

        # process.moduleLoadList.push('NativeModule ' + id)

        native_module = new(context, id)
        native_module.compile
        native_module.cache
        native_module.exports
      end

      def exist?(id)
        SOURCES.key?(id)
      end

      def cache
        @cache ||= {}
      end

      def sources
        @sources ||= Hash.new do |hash, id|
          hash[id] = SOURCES[id].call
        end
      end
    end

    attr_accessor :id, :filename, :exports, :loaded

    def initialize(context, id)
      @context  = context
      @filename = id + '.js'
      @id       = id
      @exports  = context.new_object
      @loaded   = false
    end

    def compile
      wrapped   = Module.wrap(self.class.sources[id])
      function  = @context.runtime.eval(wrapped, filename)

      function.call exports, @context.new_function(require_proc), self, filename

      @loaded = true
    end

    def cache
      self.class.cache[id] = self
    end

    private
      def require_proc
        @require_proc ||= lambda do |_, path|
          NativeModule.require @context, path
        end
      end
  end
end
