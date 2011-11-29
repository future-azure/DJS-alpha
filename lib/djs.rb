
require 'thread'

module DJS
  TYPE_HANDSHAKE = 0
  TYPE_CONNECT   = 1
  TYPE_RESPONSE  = 2
  TYPE_MESSAGE   = 3
  TYPE_CLOSE     = 4
  TYPE_CALLBACK  = 5
  TYPE_RECONNECT = 6
  TYPE_RPC       = 7

  class DJSError < RuntimeError; end
  class DJSBadRequestError < DJSError; end

  def start(klass = DJSConnection, config = {})
    @server = DJSServer.new(klass, config)
    DJSConnections.server = @server
  end
  module_function :start

  def stop
    puts "STOP"
  end
  module_function :stop

  def log(log)
    puts Thread.current.to_s + " " + log.to_s
  end
  module_function :log

  def response(request)
    if request =~ /\A(\d)\x00(\d+)\x00(.*)\z/
      case $1.to_i
      when TYPE_HANDSHAKE
        response = @server.handshake
      when TYPE_CONNECT
        response = @server.connect($2.to_i)
      when TYPE_RESPONSE
        response = @server.response($2.to_i, $3)
      when TYPE_MESSAGE
      when TYPE_CLOSE
      when TYPE_CALLBACK
        response = @server.callback($2.to_i, $3)
      when TYPE_RECONNECT
        response = @server.reconnect($2.to_i)
      when TYPE_RPC
        response = @server.rpc($2.to_i)
      else

      end
    else
      Thread.new do
        onerror DJSBadRequestError.new
      end
      response = nil
    end

    return response.to_s
  end
  module_function :response

  def connections
    @server.djs_connections
  end
  module_function :connections

  def add_task(conn, name, *args)
    @server.add_task(conn, name, *args)
  end
  module_function :add_task

  class DJSConnections

    def self.server=(server)
      @@server = server
    end

    def initialize(connections)
      @connections = connections
    end

    def [](pattern)
      if pattern == "*"
        return self
      end
      DJSConnections.new(Hash.new)
    end

    def method_missing(name, *args)
      @connections.values.each { |conn|
        next unless conn.type == :main
        rpc_conn = @@server.create_rpc_connection(conn.cid, name, args)
        prx = DJSRpcProxyObject.new(rpc_conn)
        conn.add_proxy(prx, true)
      }
    end
  end

  class DJSServer
    TERMINAL = "\x00"
    RECONNECT = ""

    def initialize(klass = nil, config = {})
      @klass = klass
      @config = config

      @fiber = nil
      @connections = Hash.new
      @djs_connections = DJSConnections.new(@connections)
      @tasks = Queue.new
      @group = ThreadGroup.new
      @thread = run
    end
    attr_reader :connections, :djs_connections, :fiber

    def run
      Thread.start do
        begin
          while true
            main_loop
          end
        ensure
          # TODO kill thread
        end
      end
    end

    def main_loop
      Thread.start(@tasks.pop) do |task|
        conn = task[0]
        name = task[1]
        args = task[2]
        @fiber = Fiber.new do
          if args
            conn.send(name, *args)
          else
            conn.send(name)
          end
          conn.add_proxy(nil, true)
          TERMINAL
        end
        req = @fiber.resume
        if req == TERMINAL
          if conn.type == :main
            conn.request.push RECONNECT
          else
            @connections.delete(conn.__id__)
            conn.request.push TERMINAL
            return
          end
        else
          conn.request.push req
        end
        while rsp = conn.response.pop
          req = @fiber.resume(rsp)
          if req == TERMINAL
            if conn.type == :main
              conn.request.push RECONNECT
            else
              @connections.delete(conn.__id__)
              conn.request.push TERMINAL
              return
            end
          else
            conn.request.push req
          end
        end
      end
    end

    def handshake
      conn = @klass.new(:main)
      @connections[conn.__id__] = conn
      return conn.__id__.to_s
    end

    def connect(id)
      conn = @connections[id]
      add_task conn, :on_open
      req = conn.request.pop
      return req
    end

    def reconnect(id)
      conn = @connections[id]
      req = conn.request.pop
      return req
    end

    def response(id, rsp)
      conn = @connections[id]
      conn.response.push rsp
      req = conn.request.pop
      return req
    end

    def callback(cid, method)
      conn = @klass.new(:callback, cid)
      @connections[conn.__id__] = conn
      add_task conn, :on_callback, method
      req = conn.request.pop
      return conn.__id__.to_s + "\x00" + req
    end

    def rpc(id)
      conn = @connections[id]
      add_task conn, conn.rpc[0], conn.rpc[1]
      req = conn.request.pop
      return req
    end

    def add_task(conn, name, *args)
      @tasks.push [conn, name, args]
    end

    def create_rpc_connection(cid, name, args)
      conn = @klass.new(:rpc, cid)
      @connections[conn.__id__] = conn
      conn.set_rpc(name, args)
      return conn
    end
  end

  class DJSConnection
    SEP = "\x00"

    def initialize(type, cid = 0)
      @type = type
      if @type == :main
        @cid = self.__id__
      else
        @cid = cid
      end
      @request = Queue.new
      @response = Queue.new
      @proxies = Hash.new
      @proxy_ids = Array.new
      @mutex = Mutex.new
    end

    attr_accessor :type, :request, :response, :proxies
    attr_reader :cid

    def set_rpc(name, args)
      @rpc = [name, args]
    end

    def rpc
      @rpc
    end

    def add_proxy(proxy, flush_now = false)
      @mutex.synchronize {
        if proxy
          @proxy_ids << proxy.__id__
          @proxies[proxy.__id__] = proxy
        end
        # TODO length
        if flush_now || @proxy_ids.length == 100
          flush
        end
      }
    end

    def flush
      if @proxy_ids.empty?
        return
      end

      json = "0\x00"
      @proxy_ids.each { |id|
        json << @proxies[id].__json << SEP
      }
      json[-1] = ""
      rsp = Fiber.yield(json)
      while rsp != '{}'
        info = eval(rsp)

        if info.key?("type")
          result = info["type"].send(info["content"], *info["args"])
          proxy = @proxies[info["id"]]
          proxy = @proxies[proxy.info[:id]]
          proxy.origin = result
          proxy.solved = true

          json = "1\x00{\"id\":" + DJS.to_json(info["id"]) + ",\"origin\":" + DJS.to_json(result) + "}"
          rsp = Fiber.yield(json)
        else
          info.each { |key, value|
            if @proxies.key?(key)
              @proxies[key].origin = value
              @proxies[key].solved = true
            end
          }
          rsp = "{}"
        end
      end

      @proxies.clear
      @proxy_ids.clear
    end

    def on_callback(method)
      self.method(method).call
    end

    # Event handler
    def on_open

    end

    def on_close

    end

    def on_message(msg)

    end

    def on_error(err)

    end

    # Root Javascript Object
    def window
      DJSProxyObject.new(self, {:type => :window})
    end

    def document
      DJSProxyObject.new(self, {:type => :document})
    end

    def frame
      DJSProxyObject.new(self, {:type => :Frame})
    end

    def history
      DJSProxyObject.new(self, {:type => :history})
    end

    def location
      DJSProxyObject.new(self, {:type => :location})
    end
  end

  class DJSProxyObject
    def initialize(conn, info)
      @conn = conn
      @info = info
      @origin = nil
      @solved = false
      @info[:id] = __id__
      @info[:cid] = conn.cid
    end

    attr_accessor :origin, :solved, :info

    def method_missing(name, *args, &block)
      if @solved
        return @origin.send(name, *args, &block)
      end

      if block
        @conn.add_proxy(nil, true)
        return @origin.send(name, *args, &block)
      end

      if name.to_s =~ /^.*=$/ && args && Symbol === args[0]
        name = "{}" + name.to_s[/[^=]+/]
      end

      proxy = DJSProxyObject.new(@conn, {:type => self, :content => name, :args => args})
      @conn.add_proxy proxy
      return proxy
    end

    def sync
      return @origin if @solved
      @conn.add_proxy(nil, true)
      return @solved ? @origin : self
    end

    def __json
      DJS.to_json @info
    end

    def __to_s
      #TODO refs
      if DJSProxyObject === @info[:type]
        return "REFS[" + __id__.to_s + "].origin"
      else
        return @info[:type].to_s
      end
    end
  end

  class DJSRpcProxyObject < DJSProxyObject
    def initialize(conn)
      super(conn, {:type => 'rpc', :content => conn.__id__})
    end
  end

  def to_json(obj)
    case obj
    when Hash
      json = '{'
      obj.each { |key, value|
        json << '"' << key.to_s << '":' << to_json(value) << ','
      }
      if (json.length > 1)
        json[-1] = '}'
      else
        json << '}'
      end
      return json
    when Array
      json = '['
      obj.each { |item|
        json << to_json(item) << ','
      }
      if (json.length > 1)
        json[-1] = ']'
      else
        json << ']'
      end
      return json
    when DJSProxyObject
      return obj.__to_s
    when Numeric
      return obj.to_s
    when String
      return '"' + obj.gsub('"', '\\"') + '"'
    when TrueClass, FalseClass
      return obj.to_s
    else
      return '"' + obj.to_s + '"'
    end
  end
  module_function :to_json
end
