require "file_utils"
require "socket"
require "http"

# ---------------------------------
# -------------- FFI --------------
# ---------------------------------

# Was running into issues using calling ruby so
# all of this basically only allows echo/print 
# methods to be called so far.
{% if env("DRAGONSTONE_RUBY_LIB") %}
    @[Link({{ env("DRAGONSTONE_RUBY_LIB") }})]

    lib LibRuby
        alias VALUE = Void*
        alias ID    = LibC::ULong

        fun ruby_setup : LibC::Int
        fun rb_intern(name : LibC::Char*) : ID
        fun rb_funcall(recv : VALUE, mid : ID, argc : LibC::Int, ...) : VALUE
        fun rb_utf8_str_new_cstr(str : LibC::Char*) : VALUE
        fun rb_int2inum(num : LibC::LongLong) : VALUE
        fun rb_float_new(num : Float64) : VALUE
        fun rb_ary_new : VALUE
        fun rb_ary_push(ary : VALUE, item : VALUE) : VALUE

        $rb_cObject : VALUE
    end
{% end %}

lib LibC
    fun getchar : Int32

    {% if flag?(:windows) %}
        fun _write(fd : Int32, buf : UInt8*, count : UInt32) : Int32
    {% end %}
end

module Dragonstone
    module FFI
        alias InteropValue = Nil | Bool | Int32 | Int64 | Float64 | String | Char | Array(InteropValue)

        @@net_next_handle : Int64 = 1_i64
        @@net_listeners = {} of Int64 => TCPServer
        @@net_clients = {} of Int64 => TCPSocket

        RUBY_BRIDGE_ENABLED = {{ env("DRAGONSTONE_RUBY_LIB")    ? true : false }}

        {% if env("DRAGONSTONE_RUBY_LIB") %}
            @@ruby_initialized = false

            def self.ruby_available? : Bool
                true
            end

            def self.ensure_ruby_runtime
                return if @@ruby_initialized

                status = LibRuby.ruby_setup

                raise "Failed to initialize embedded Ruby runtime (code #{status})" unless status == 0

                @@ruby_initialized = true
            end

            def self.call_ruby(method_name : String, arguments : Array(InteropValue)) : InteropValue
                ensure_ruby_runtime

                method_id = LibRuby.rb_intern(method_name)

                last_result = LibRuby::VALUE.null

                if arguments.empty?
                    last_result = LibRuby.rb_funcall(LibRuby.rb_cObject, method_id, 0)
                else
                    arguments.each do |argument|
                        ruby_value = to_ruby_value(argument)
                        last_result = LibRuby.rb_funcall(LibRuby.rb_cObject, method_id, 1, ruby_value)
                    end
                end

                from_ruby_value(last_result)
            end

            private def self.to_ruby_value(value : InteropValue) : LibRuby::VALUE
                ensure_ruby_runtime

                case value
                when Nil
                    LibRuby::VALUE.null

                when Bool
                    LibRuby.rb_utf8_str_new_cstr(value ? "true" : "false")

                when Int32, Int64
                    LibRuby.rb_int2inum(value.to_i64)

                when Float64
                    LibRuby.rb_float_new(value)

                when Char
                    LibRuby.rb_utf8_str_new_cstr(value.to_s)

                when String
                    LibRuby.rb_utf8_str_new_cstr(value)

                when Array
                    ruby_array = LibRuby.rb_ary_new
                    value.each { |element| LibRuby.rb_ary_push(ruby_array, to_ruby_value(element)) }
                    ruby_array

                else
                    LibRuby.rb_utf8_str_new_cstr(value.to_s)

                end
            end

            private def self.from_ruby_value(value : LibRuby::VALUE) : InteropValue
                # The Ruby entry points we invoke (`puts`/`print`) return nil, so
                # we can expose nil to the Dragonstone side for now.
                nil
            end
        {% else %}
            def self.ruby_available? : Bool
                false
            end

            def self.ensure_ruby_runtime
                # There's no interop when Ruby FFI is disabled.
            end

            def self.call_ruby(method_name : String, arguments : Array(InteropValue)) : InteropValue
                # A fallback to Crystal implementations when Ruby FFI is unavailable.
                call_crystal(method_name, arguments)
            end
        {% end %}

        def self.call_crystal(function_name : String, arguments : Array(InteropValue)) : InteropValue
            case function_name

            when "echo", "puts"
                arguments.each { |argument| puts format_value(argument) }
                nil

            when "print"
                arguments.each { |argument| print format_value(argument) }
                nil

            when "file_open"
                path = expect_string(arguments, 0, function_name)
                mode = expect_optional_string(arguments, 1, function_name, default: "r")
                create_dirs = expect_optional_bool(arguments, 2, function_name, default: false)

                expanded = File.expand_path(path)

                ensure_parent_directories(expanded) if create_dirs

                case mode
                when "r"
                    raise "#{function_name}('#{path}', 'r') failed: file does not exist" unless File.exists?(expanded)
                    raise "#{function_name}('#{path}', 'r') failed: '#{path}' is not a regular file" unless File.file?(expanded)
                when "w"
                    ensure_parent_directories(expanded)
                    File.touch(expanded)
                when "a"
                    ensure_parent_directories(expanded)
                    File.touch(expanded)
                else
                    raise "#{function_name} invalid mode '#{mode}' (expected 'r', 'w' or 'a')"
                end

                info = [] of InteropValue
                info << display_path(expanded)
                info << mode
                info << File.exists?(expanded)
                info << (File.exists?(expanded) && File.file?(expanded) ? File.size(expanded) : nil)
                info

            when "file_read"
                path = expect_string(arguments, 0, function_name)
                safe_io(function_name, path) { File.read(path) }

            when "file_write"
                path = expect_string(arguments, 0, function_name)
                content = expect_string(arguments, 1, function_name)
                create_dirs = expect_optional_bool(arguments, 2, function_name, default: false)

                ensure_parent_directories(path) if create_dirs

                safe_io(function_name, path) do
                    File.write(path, content)
                    content.bytesize
                end

            when "file_append"
                path = expect_string(arguments, 0, function_name)
                content = expect_string(arguments, 1, function_name)
                create = expect_optional_bool(arguments, 2, function_name, default: true)

                ensure_parent_directories(path) if create
                File.touch(path) if create && !File.exists?(path)

                safe_io(function_name, path) do
                    File.open(path, "a") { |io| io.print(content) }
                    content.bytesize
                end

            when "file_create"
                path = expect_string(arguments, 0, function_name)
                contents = arguments[1]? if arguments.size >= 2
                create_dirs = expect_optional_bool(arguments, 2, function_name, default: true)

                ensure_parent_directories(path) if create_dirs

                safe_io(function_name, path) do
                    case contents
                    when String
                        File.write(path, contents)
                    when Nil, Bool, Int32, Int64, Float64, Char
                        File.write(path, contents.to_s)
                    when Array(InteropValue)
                        serialized = contents.map { |element| format_value(element) }.join("\n")
                        File.write(path, serialized)
                    else
                        File.touch(path)
                    end
                end

                display_path(File.expand_path(path))

            when "file_delete"
                path = expect_string(arguments, 0, function_name)

                return false unless File.exists?(path) || Dir.exists?(path)

                safe_io(function_name, path) do
                    if File.file?(path)
                        File.delete(path)
                    elsif Dir.exists?(path)
                        FileUtils.rm_rf(path)
                    end
                end

                true

            when "path_create"
                raw = expect_optional_string(arguments, 0, function_name, default: ".")
                expanded = File.expand_path(raw)
                ensure_parent_directories(expanded)
                Dir.mkdir(expanded) unless Dir.exists?(expanded)
                display_path(expanded)

            when "path_normalize"
                raw = expect_optional_string(arguments, 0, function_name, default: ".")
                Path.new(raw).normalize.to_s.gsub("\\", "/")

            when "path_parent"
                raw = expect_optional_string(arguments, 0, function_name, default: ".")
                parent = Path.new(raw).parent
                parent ? parent.to_s.gsub("\\", "/") : "."

            when "path_base"
                raw = expect_string(arguments, 0, function_name)
                Path.new(raw).basename

            when "path_expand"
                raw = expect_optional_string(arguments, 0, function_name, default: ".")
                display_path(File.expand_path(raw))

            when "path_delete"
                raw = expect_optional_string(arguments, 0, function_name, default: ".")
                normalized = Path.new(raw).normalize
                parent = normalized.parent
                return "." unless parent

                parent_str = parent.to_s.gsub("\\", "/")
                parent_str.empty? ? "." : (parent_str == "." ? "./" : parent_str)

            when "net_listen_tcp"
                host = expect_optional_string(arguments, 0, function_name, default: "0.0.0.0")
                port = expect_int(arguments, 1, function_name)
                backlog = expect_optional_int(arguments, 2, function_name, default: 128)

                server = TCPServer.new(host, port, backlog)
                handle = next_net_handle
                @@net_listeners[handle] = server
                handle

            when "net_accept_request"
                listener_id = expect_int(arguments, 0, function_name)
                server = @@net_listeners[listener_id]? || raise "#{function_name} unknown listener #{listener_id}"

                client = server.accept?
                raise "#{function_name} failed to accept connection" unless client

                parsed = HTTP::Request.from_io(client)
                unless parsed.is_a?(HTTP::Request)
                    status = parsed.is_a?(HTTP::Status) ? parsed.code : 400
                    client.puts("HTTP/1.1 #{status} Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                    client.flush
                    client.close
                    raise "#{function_name} failed to parse request"
                end

                body_io = parsed.body
                body = body_io ? body_io.gets_to_end : ""
                headers = [] of InteropValue
                parsed.headers.each do |name, values|
                    values.each do |value|
                        pair = [] of InteropValue
                        pair << name
                        pair << value
                        headers << pair
                    end
                end
                remote = client.remote_address.to_s

                client_id = next_net_handle
                @@net_clients[client_id] = client

                result = [] of InteropValue
                result << client_id
                result << parsed.method
                result << parsed.path
                result << headers
                result << body
                result << remote
                result

            when "net_send_response"
                client_id = expect_int(arguments, 0, function_name)
                status = expect_int(arguments, 1, function_name)
                headers = expect_headers(arguments, 2, function_name)
                body = expect_optional_string(arguments, 3, function_name, default: "")

                socket = @@net_clients[client_id]? || raise "#{function_name} unknown client #{client_id}"

                reason = status_reason(status)

                # Always ensure Content-Length and Connection headers.
                has_content_length = false
                has_connection = false

                socket << "HTTP/1.1 #{status} #{reason}\r\n"
                headers.each do |pair|
                    name = pair[0].as(String)
                    value = pair[1].as(String)
                    has_content_length ||= name.downcase == "content-length"
                    has_connection ||= name.downcase == "connection"
                    socket << "#{name}: #{value}\r\n"
                end

                unless has_content_length
                    socket << "Content-Length: #{body.bytesize}\r\n"
                end
                socket << "Connection: close\r\n" unless has_connection
                socket << "\r\n"
                socket << body
                socket.flush
                nil

            when "net_close"
                handle = expect_int(arguments, 0, function_name)
                if listener = @@net_listeners.delete(handle)
                    listener.close
                    nil
                elsif client = @@net_clients.delete(handle)
                    client.close
                    nil
                else
                    raise "#{function_name} unknown handle #{handle}"
                end

            when "env_get"
                key = expect_string(arguments, 0, function_name)
                ENV[key]?

            # when "chr"
            #     code = expect_int(arguments, 0, function_name)
            #     raise "#{function_name} codepoint out of range" unless code >= 0 && code <= 0x10FFFF
            #     code.chr

            else
                raise "Unknown Crystal function: #{function_name}"
            end
        end

        def self.call_c(function_name : String, arguments : Array(InteropValue)) : InteropValue
            case function_name

            when "printf"
                format_value = expect_string(arguments, 0, function_name)
                LibC.printf(format_value)
            
            when "getchar"
                # Calls the C standard library getchar()
                # Returns the character as an integer (ASCII) or -1 for EOF
                LibC.getchar

            when "write"
                # Usage: ffi.call_c("write", [fd, content, length])
                # (If length is omitted, uses content.bytesize.)
                fd = expect_int(arguments, 0, function_name)
                content = expect_string(arguments, 1, function_name)
                count = if arguments.size >= 3
                    expect_int(arguments, 2, function_name)
                else
                    content.bytesize
                end
                
                # Calls C write(int fd, const void *buf, size_t count)
                # content.to_unsafe passes the raw C pointer (char*)
                buf = content.to_unsafe

                {% if flag?(:windows) %}
                    LibC._write(fd, buf, count.to_u32).to_i64
                {% else %}
                    capped = Math.min(count, content.bytesize)
                    {% if flag?(:bits32) %}
                        LibC.write(fd.to_i, buf.as(Void*), capped.to_u32).to_i64
                    {% else %}
                        LibC.write(fd.to_i, buf.as(Void*), capped.to_u64).to_i64
                    {% end %}
                {% end %}
            
            when "chr" 
                code = expect_int(arguments, 0, function_name)
                code.chr
            
            when "fsync"
                fd = expect_int(arguments, 0, function_name)

                {% if flag?(:windows) %}
                    LibC._commit(fd)            # might require a binding -> fun _commit(fd : Int32) : Int32
                {% else %}
                    LibC.fsync(fd)
                {% end %}

            else
                raise "Unknown C function: #{function_name}"
            end
        end

        def self.normalize(value) : InteropValue
            case value

            when Nil, Bool, Int32, Int64, Float64, String, Char
                value
            
            when Array
                normalized = [] of InteropValue
                value.each { |element| normalized << normalize(element) }
                normalized

            else
                raise "Unsupported FFI Value: #{value.inspect}"
            end
        end

        def self.format_value(value : InteropValue) : String
            case value

            when String then value

            when Nil then "nil"

            when Bool, Int32, Int64, Float64 then value.to_s

            when Char then value.to_s

            when Array then "[#{value.map { |element| format_value(element) }.join(", ")}]"

            else value.to_s
                
            end
        end

        private def self.expect_string(arguments : Array(InteropValue), index : Int32, function_name : String) : String
            value = arguments[index]? || raise "#{function_name} requires argument #{index + 1}"
            value.as?(String) || raise "#{function_name} argument #{index + 1} must be a String"
        rescue TypeCastError
            raise "#{function_name} argument #{index + 1} must be a String"
        end

        private def self.expect_optional_string(arguments : Array(InteropValue), index : Int32, function_name : String, *, default : String) : String
            value = arguments[index]?
            return default unless value
            value.as?(String) || raise "#{function_name} argument #{index + 1} must be a String"
        rescue TypeCastError
            raise "#{function_name} argument #{index + 1} must be a String"
        end

        private def self.expect_optional_bool(arguments : Array(InteropValue), index : Int32, function_name : String, *, default : Bool) : Bool
            value = arguments[index]?
            return default unless value
            value.as?(Bool) || raise "#{function_name} argument #{index + 1} must be a Bool"
        rescue TypeCastError
            raise "#{function_name} argument #{index + 1} must be a Bool"
        end

        private def self.expect_int(arguments : Array(InteropValue), index : Int32, function_name : String) : Int32
            value = arguments[index]? || raise "#{function_name} requires argument #{index + 1}"
            raw = value.as?(Int32) || value.as?(Int64) || raise "#{function_name} argument #{index + 1} must be an Int"
            raw.to_i
        rescue TypeCastError
            raise "#{function_name} argument #{index + 1} must be an Int"
        end

        private def self.expect_optional_int(arguments : Array(InteropValue), index : Int32, function_name : String, *, default : Int32) : Int32
            value = arguments[index]?
            return default unless value
            raw = value.as?(Int32) || value.as?(Int64) || raise "#{function_name} argument #{index + 1} must be an Int"
            raw.to_i
        rescue TypeCastError
            raise "#{function_name} argument #{index + 1} must be an Int"
        end

        private def self.expect_headers(arguments : Array(InteropValue), index : Int32, function_name : String) : Array(Array(InteropValue))
            value = arguments[index]? || [] of Array(InteropValue)
            headers = value.as?(Array(InteropValue)) || raise "#{function_name} argument #{index + 1} must be an Array of [String, String]"
            normalized = [] of Array(InteropValue)
            headers.each do |pair|
                tuple = pair.as?(Array(InteropValue)) || raise "#{function_name} headers must be an Array of [String, String]"
                name = tuple[0]?.as?(String) || raise "#{function_name} header name must be a String"
                val = tuple[1]?.as?(String) || raise "#{function_name} header value must be a String"
                normalized << [name.as(InteropValue), val.as(InteropValue)]
            end
            normalized
        rescue TypeCastError
            raise "#{function_name} argument #{index + 1} must be an Array of [String, String]"
        end

        private def self.ensure_parent_directories(path : String)
            parent = File.dirname(path)
            return if parent.nil? || parent.empty? || parent == "."

            FileUtils.mkdir_p(parent) unless Dir.exists?(parent)
        end

        private def self.safe_io(function_name : String, path : String, &block : -> InteropValue) : InteropValue
            yield
        rescue ex : Exception
            raise "#{function_name} failed for '#{path}': #{ex.message}"
        end

        private def self.display_path(path : String) : String
            absolute = File.expand_path(path)
            expanded = Path.new(absolute)
            begin
                current = Path.new(Dir.current)
                relative = expanded.relative_to(current)
                text = relative.to_s
                if text.empty?
                    "."
                elsif text.starts_with?(".")
                    text.gsub("\\", "/")
                else
                    "./#{text.gsub("\\", "/")}"
                end
            rescue ArgumentError
                expanded.to_s.gsub("\\", "/")
            end
        end

        private def self.next_net_handle : Int64
            handle = @@net_next_handle
            @@net_next_handle += 1
            handle
        end

        private def self.status_reason(status : Int32) : String
            case status
            when 200 then "OK"
            when 201 then "Created"
            when 202 then "Accepted"
            when 204 then "No Content"
            when 301 then "Moved Permanently"
            when 302 then "Found"
            when 304 then "Not Modified"
            when 400 then "Bad Request"
            when 401 then "Unauthorized"
            when 403 then "Forbidden"
            when 404 then "Not Found"
            when 405 then "Method Not Allowed"
            when 408 then "Request Timeout"
            when 409 then "Conflict"
            when 413 then "Payload Too Large"
            when 414 then "URI Too Long"
            when 415 then "Unsupported Media Type"
            when 418 then "I'm a teapot"
            when 429 then "Too Many Requests"
            when 500 then "Internal Server Error"
            when 501 then "Not Implemented"
            when 502 then "Bad Gateway"
            when 503 then "Service Unavailable"
            else "OK"
            end
        end
    end
end
