module Bluenode
  class Module
    class << self
      def wrap(script)
        "(function(exports, require, module, __filename, __dirname) {\n#{script}\n})"
      end
    end

    attr_accessor :id, :filename, :exports, :loaded, :paths
    attr_reader :parent, :children
    alias :loaded? :loaded

    def initialize(context, id, parent = nil)
      @context  = context
      @id       = id
      @exports  = context.new_object
      @parent   = parent

      parent.children << self if parent

      @filename = nil
      @loaded   = false
      @children = []
      @paths    = []
    end

    def load(filename)
      raise LoadError, 'module already loaded' if loaded?

      @filename = filename
      @paths = @context.class.node_module_paths(File.dirname(filename))

      extension = File.extname(filename)
      extension = '.js' if extension.nil? || extension == ''
      extension = '.js' unless @context.extensions.key?(extension)

      @context.extensions[extension].call self, filename

      @loaded = true
    end

    def require(request)
      filename  = resolve(request)
      cached    = @context.modules[filename]

      return cached.exports if cached

      return NativeModule.require(@context, filename) if NativeModule.exist?(filename)

      mod = self.class.new(@context, filename, self)

      @context.modules[filename] = mod

      had_exception = true

      begin
        mod.load filename
        had_exception = false
      ensure
        @context.modules.delete(filename) if had_exception
      end

      mod.exports
    end

    private
      def resolve(request)
        return request if NativeModule.exist?(request)

        id, paths = resolve_lookup_paths(request)
        filename  = @context.find_path(request, paths)

        filename or raise LoadError, "cannot find module '#{request}'"
      end

      def compile(content, filename)
        props = {
          main:       @context.process.mainModule,
          cache:      @context.modules,
          extensions: @context.extensions,
          resolve:    resolve_proc
        }

        wrapped     = self.class.wrap(content.sub(/^#!.*/, ''))
        function    = @context.runtime.eval(wrapped, filename)
        dirname     = File.dirname(filename)
        v8_require  = @context.new_function(require_proc, props)
        args        = [exports, v8_require, self, filename, dirname]

        function.methodcall exports, *args
      end

      def require_proc
        @require_proc ||= lambda do |_, path|
          raise LoadError, 'path must be a string' unless path.is_a?(String)

          require path
        end
      end

      def resolve_proc
        @resolve_proc ||= lambda do |_, request|
          resolve request
        end
      end

      def resolve_lookup_paths(request)
        return [request, []] if NativeModule.exist?(request)

        start = request[0..1]

        if start != './' && start != '..'
          main_paths = @context.global_paths
          main_paths = paths.concat(main_paths)

          return [request, main_paths]
        end

        unless filename
          main_paths = ['.'].concat(@context.global_paths)
          main_paths = @context.class.node_module_paths('.').concat(main_paths)

          return [request, main_paths]
        end

        is_index  = File.basename(filename) =~ /^index(\.\w+)*$/
        id_path   = is_index ? id : File.dirname(id)
        id        = File.expand_path(request, id_path)

        if id_path == '.' && id.index('/').nil?
          id = './' + id
        end

        [id, [File.dirname(filename)]]
      end
  end
end
