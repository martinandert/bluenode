require 'json'
require 'rbconfig'

module Bluenode
  class Context
    class << self
      def main(basedir = Dir.pwd)
        context = new(basedir)
        context.require './'
      end

      def node_module_paths(from)
        from = File.expand_path(from)

        split_re  = windows? && /[\/\\]/ || /\//
        paths     = []
        parts     = from.split(split_re)
        tip       = parts.size - 1

        while tip >= 0
          if parts[tip] != 'node_modules'
            dir = File.join(*parts[0..tip], 'node_modules')
            paths << dir
          end

          tip -= 1
        end

        paths
      end

      def windows?
        @windows ||= !!(RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/)
      end
    end

    attr_reader :runtime, :basedir

    def initialize(basedir = Dir.pwd, env = ENV.dup, stdout = $stdout, stderr = $stderr)
      @runtime  = V8::Context.new
      @basedir  = basedir.to_s

      startup env, stdout, stderr
    end

    def process
      @runtime['process']
    end

    def eval_as_module(script, name = '[eval]', is_main = false)
      Module.new(self, name).tap do |mod|
        mod.filename  = File.join(basedir, name)
        mod.paths     = self.class.node_module_paths(basedir)

        if is_main
          runtime['process'].mainModule = mod
          mod.id = '.'
        end

        mod.send :compile, script, "#{name}-wrapper"
      end
    end

    def require(path)
      script  = "module.exports = require('#{path}')"
      mod     = eval_as_module(script, '[main]', true)

      mod.exports
    end

    def new_object
      @runtime['Object'].new
    end

    def new_function(callable, props = {})
      @runtime.enter do
        function = @runtime.to_v8(callable)

        props.each do |name, value|
          function.Set @runtime.to_v8(name.to_s), @runtime.to_v8(value)
        end

        function
      end
    end

    def modules
      @modules ||= {}
    end

    def extensions
      @extensions ||= {}.tap do |extensions|
        extensions['.js'] = lambda do |mod, filename|
          mod.send :compile, File.read(filename), filename
        end

        extensions['.json'] = lambda do |mod, filename|
          begin
            mod.exports = JSON.parse(File.read(filename))
          rescue => exc
            raise $!, "#{filename}: #{$!}", $!.backtrace
          end
        end

        extensions['.node'] = lambda do |mod, filename|
          raise 'requiring modules with a .node extension is not supported'
        end
      end
    end

    def global_paths
      @global_paths ||= begin
        home_dir  = self.class.windows? && ENV['USERPROFILE'] || ENV['HOME']
        exec_path = `which node`.chomp

        paths = [File.expand_path(File.join('..', '..', 'lib', 'node'), exec_path)]

        if home_dir
          paths.unshift File.expand_path('.node_libraries', home_dir)
          paths.unshift File.expand_path('.node_modules', home_dir)
        end

        if node_path = ENV['NODE_PATH']
          paths = node_path.split(File::PATH_SEPARATOR).concat(paths)
        end

        paths
      end
    end

    def find_path(request, paths)
      exts  = extensions.keys
      paths = [''] if request[0] == '/'
      trailing_slash = request[-1] == '/'
      cache_key = { request: request, paths: paths }.to_json

      return path_cache[cache_key] if path_cache.key?(cache_key)

      i, ii = 0, paths.size

      while i < ii
        base_path = File.expand_path(request, paths[i])
        filename = nil

        unless trailing_slash
          filename = try_file(base_path)
          filename = try_extensions(base_path, exts) unless filename
        end

        filename = try_package(base_path, exts) unless filename
        filename = try_extensions(File.expand_path('index', base_path), exts) unless filename

        if filename
          path_cache[cache_key] = filename
          return filename
        end

        i += 1
      end

      false
    end

    private
      def path_cache
        @path_cache ||= {}
      end

      def realpath_cache
        @realpath_cache ||= {}
      end

      def package_main_cache
        @package_main_cache ||= {}
      end

      def try_file(path)
        return false unless File.file?(path)

        realpath_cache[path] ||= File.realpath(path)
      end

      def try_extensions(path, exts)
        i, ii = 0, exts.size

        while i < ii
          filename = try_file(path + exts[i])
          return filename if filename

          i += 1
        end

        false
      end

      def try_package(path, exts)
        pkg = read_package(path)

        return false unless pkg

        filename = File.expand_path(pkg, path)

        try_file(filename) || try_extensions(filename, exts) || try_extensions(File.expand_path('index', filename), exts)
      end

      def read_package(path)
        return package_main_cache[path] if package_main_cache.key?(path)

        begin
          json_path = File.expand_path('package.json', path)
          json = File.read(json_path)
        rescue => exc
          return false
        end

        package_main_cache[path] = JSON.parse(json)['main']
      rescue => exc
        raise $!, "error parsing #{json_path}: #{$!}", $!.backtrace
      end

      def startup(env, stdout, stderr)
        function = runtime.eval <<-EOS
          var global = this;

          (function(process) {
            global.process = process;
            global.global = global;
            global.GLOBAL = global;
            global.root = global;
            global.Buffer = function Buffer() { throw new Error('global.Buffer is not supported'); };

            function noop() {};

            process.domain = null;
            process.on = noop;
            process.once = noop;
            process.off = noop;
            process.addListener = noop;
            process.removeListener = noop;
            process.removeAllListeners = noop;
            process.emit = noop;

            process.chdir = function(dir) {
              throw new Error('process.chdir is not supported');
            };

            process.umask = function() { return 0; };
          })
        EOS

        process = {
          title: $0,
          pid: Process.pid,
          env: env,

          cwd: lambda { |*args| basedir },

          stdout: {
            write: lambda do |_, chunk, *args|
              stdout.write chunk
              true
            end
          },

          stderr: {
            write: lambda do |_, chunk, *args|
              stderr.write chunk
              true
            end
          }
        }

        function.call process

        runtime['global'].console = NativeModule.require(self, 'console')
      end
  end
end
