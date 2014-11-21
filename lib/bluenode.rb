require 'bluenode/version'
require 'v8'
require 'ref'

# do not use TRR's built-in weakref implementation
V8::Weak.send :remove_const, :Ref
V8::Weak::Ref = Ref::WeakReference
V8::Weak.send :remove_const, :WeakValueMap
V8::Weak::WeakValueMap = Ref::WeakValueMap

module Bluenode
  autoload :Context,      'bluenode/context'
  autoload :Module,       'bluenode/module'
  autoload :NativeModule, 'bluenode/native_module'
end
