require "file_utils"
require "socket"
require "http"
require "../runtime/abi/abi"

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

        private RELATIVE_DERIVED_GENERAL_CATEGORY = "src/dragonstone/stdlib/modules/shared/unicode/proc/UCD/extracted/DerivedGeneralCategory.txt"
        private RELATIVE_DERIVED_COMBINING_CLASS = "src/dragonstone/stdlib/modules/shared/unicode/proc/UCD/extracted/DerivedCombiningClass.txt"

        @@general_category_ranges : Array(Tuple(String, Array(Tuple(Int32, Int32))))?
        @@combining_class_ranges : Array(Tuple(Int32, Int32, Int32))?
        @@warned_missing_general_category = false
        @@warned_missing_combining_class = false

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
                arguments.each { |argument| write_stdout(format_value(argument), newline: true) }
                nil

            when "print"
                arguments.each { |argument| write_stdout(format_value(argument), newline: false) }
                nil

            when "file_open"
                path = expect_string(arguments, 0, function_name)
                mode = expect_optional_string(arguments, 1, function_name, default: "r")
                create_dirs = expect_optional_bool(arguments, 2, function_name, default: false)
                expanded = abi_path_expand(path)

                if create_dirs
                    parent = abi_path_parent(path)
                    if parent != "." && parent != "./"
                        abi_path_create(parent)
                    end
                end

                case mode
                when "r"
                    raise "#{function_name}('#{path}', 'r') failed: file does not exist" unless abi_file_exists?(path)
                    raise "#{function_name}('#{path}', 'r') failed: '#{path}' is not a regular file" unless abi_file_is_file?(path)
                when "w"
                    ensure_write = DragonstoneABI.dragonstone_file_write(path, Pointer(UInt8).null, 0, 0)
                    raise "#{function_name}('#{path}', 'w') failed to create file" if ensure_write < 0
                when "a"
                    ensure_write = DragonstoneABI.dragonstone_file_write(path, Pointer(UInt8).null, 0, 1)
                    raise "#{function_name}('#{path}', 'a') failed to create file" if ensure_write < 0
                else
                    raise "#{function_name} invalid mode '#{mode}' (expected 'r', 'w' or 'a')"
                end

                exists = abi_file_exists?(path)
                size = abi_file_size(path)

                info = [] of InteropValue
                info << display_path(expanded)
                info << mode
                info << exists
                info << (exists && abi_file_is_file?(path) && size >= 0 ? size : nil)
                info

            when "file_read"
                path = expect_string(arguments, 0, function_name)
                safe_io(function_name, path) do
                    ptr = DragonstoneABI.dragonstone_file_read(path)
                    raise "#{function_name} failed for '#{path}': unable to read file" if ptr.null?
                    abi_string(ptr)
                end

            when "file_write"
                path = expect_string(arguments, 0, function_name)
                content = expect_string(arguments, 1, function_name)
                create_dirs = expect_optional_bool(arguments, 2, function_name, default: false)
                if create_dirs
                    parent = abi_path_parent(path)
                    abi_path_create(parent) if parent != "." && parent != "./"
                end

                safe_io(function_name, path) do
                    bytes = DragonstoneABI.dragonstone_file_write(path, content.to_unsafe, content.bytesize, 0)
                    raise "#{function_name} failed for '#{path}': unable to write file" if bytes < 0
                    bytes
                end

            when "file_append"
                path = expect_string(arguments, 0, function_name)
                content = expect_string(arguments, 1, function_name)
                create = expect_optional_bool(arguments, 2, function_name, default: true)
                if create
                    parent = abi_path_parent(path)
                    abi_path_create(parent) if parent != "." && parent != "./"
                end

                safe_io(function_name, path) do
                    bytes = DragonstoneABI.dragonstone_file_write(path, content.to_unsafe, content.bytesize, 1)
                    raise "#{function_name} failed for '#{path}': unable to append file" if bytes < 0
                    bytes
                end

            when "file_create"
                path = expect_string(arguments, 0, function_name)
                contents = arguments[1]? if arguments.size >= 2
                create_dirs = expect_optional_bool(arguments, 2, function_name, default: true)
                if create_dirs
                    parent = abi_path_parent(path)
                    abi_path_create(parent) if parent != "." && parent != "./"
                end

                safe_io(function_name, path) do
                    payload = case contents
                              when String
                                  contents
                              when Nil, Bool, Int32, Int64, Float64, Char
                                  contents.to_s
                              when Array(InteropValue)
                                  contents.map { |element| format_value(element) }.join("\n")
                              else
                                  ""
                              end
                    bytes = DragonstoneABI.dragonstone_file_write(path, payload.to_unsafe, payload.bytesize, 0)
                    raise "#{function_name} failed for '#{path}': unable to create file" if bytes < 0
                end

                display_path(abi_path_expand(path))

            when "file_delete"
                path = expect_string(arguments, 0, function_name)
                return false unless abi_file_exists?(path)

                safe_io(function_name, path) do
                    DragonstoneABI.dragonstone_file_delete(path) != 0
                end

            when "path_create"
                raw = expect_optional_string(arguments, 0, function_name, default: ".")
                display_path(abi_path_create(raw))

            when "path_normalize"
                raw = expect_optional_string(arguments, 0, function_name, default: ".")
                abi_path_normalize(raw)

            when "path_parent"
                raw = expect_optional_string(arguments, 0, function_name, default: ".")
                abi_path_parent(raw)

            when "path_base"
                raw = expect_string(arguments, 0, function_name)
                abi_path_base(raw)

            when "path_expand"
                raw = expect_optional_string(arguments, 0, function_name, default: ".")
                display_path(abi_path_expand(raw))

            when "path_delete"
                raw = expect_optional_string(arguments, 0, function_name, default: ".")
                abi_path_delete(raw)

            when "unicode_normalize"
                value = expect_string(arguments, 0, function_name)
                form = expect_optional_string(arguments, 1, function_name, default: "NFC")

                case form.upcase
                when "NFD"
                    value.unicode_normalize(:nfd)
                when "NFKD"
                    value.unicode_normalize(:nfkd)
                when "NFKC"
                    value.unicode_normalize(:nfkc)
                else
                    value.unicode_normalize(:nfc)
                end

            when "unicode_canonical_equivalent"
                left = expect_string(arguments, 0, function_name)
                right = expect_string(arguments, 1, function_name)
                left.unicode_normalize(:nfd) == right.unicode_normalize(:nfd)

            when "unicode_upcase"
                value = expect_string(arguments, 0, function_name)
                option = unicode_case_option(expect_optional_string(arguments, 1, function_name, default: "NONE"))
                value.upcase(option)

            when "unicode_downcase"
                value = expect_string(arguments, 0, function_name)
                option = unicode_case_option(expect_optional_string(arguments, 1, function_name, default: "NONE"))
                value.downcase(option)

            when "unicode_titlecase"
                value = expect_string(arguments, 0, function_name)
                option = unicode_case_option(expect_optional_string(arguments, 1, function_name, default: "NONE"))
                value.capitalize(option)

            when "unicode_casefold"
                value = expect_string(arguments, 0, function_name)
                value.downcase(Unicode::CaseOptions::Fold)

            when "unicode_graphemes"
                value = expect_string(arguments, 0, function_name)
                output = [] of InteropValue
                value.graphemes.each do |grapheme|
                    output << grapheme.to_s
                end
                output

            when "unicode_grapheme_count"
                value = expect_string(arguments, 0, function_name)
                value.graphemes.size

            when "unicode_general_category"
                codepoint = expect_int(arguments, 0, function_name)
                general_category_for(codepoint)

            when "unicode_combining_class"
                codepoint = expect_int(arguments, 0, function_name)
                combining_class_for(codepoint)

            when "unicode_whitespace"
                codepoint = expect_int(arguments, 0, function_name)
                char = codepoint_to_char(codepoint)
                char ? char.whitespace? : false

            when "unicode_letter"
                codepoint = expect_int(arguments, 0, function_name)
                char = codepoint_to_char(codepoint)
                char ? Unicode.letter?(char) : false

            when "unicode_number"
                codepoint = expect_int(arguments, 0, function_name)
                char = codepoint_to_char(codepoint)
                char ? Unicode.number?(char) : false

            when "unicode_mark"
                codepoint = expect_int(arguments, 0, function_name)
                char = codepoint_to_char(codepoint)
                char ? Unicode.mark?(char) : false

            when "unicode_control"
                codepoint = expect_int(arguments, 0, function_name)
                char = codepoint_to_char(codepoint)
                char ? Unicode.control?(char) : false

            when "unicode_compare"
                left = expect_string(arguments, 0, function_name)
                right = expect_string(arguments, 1, function_name)
                mode = expect_optional_string(arguments, 2, function_name, default: "DEFAULT")

                if mode.upcase == "CASEFOLD"
                    left = left.downcase(Unicode::CaseOptions::Fold)
                    right = right.downcase(Unicode::CaseOptions::Fold)
                end

                left <=> right

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

        private def self.write_stdout(text : String, newline : Bool) : Nil
            payload = text.to_slice
            DragonstoneABI.dragonstone_io_write_stdout(payload, payload.size)
            if newline
                newline_slice = "\n".to_slice
                DragonstoneABI.dragonstone_io_write_stdout(newline_slice, newline_slice.size)
            end
            DragonstoneABI.dragonstone_io_flush_stdout
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

        private def self.unicode_case_option(raw : String) : Unicode::CaseOptions
            case raw.upcase
            when "ASCII"
                Unicode::CaseOptions::ASCII
            when "TURKIC"
                Unicode::CaseOptions::Turkic
            when "FOLD"
                Unicode::CaseOptions::Fold
            else
                Unicode::CaseOptions::None
            end
        end

        private def self.codepoint_to_char(codepoint : Int32) : Char?
            return nil if codepoint < 0 || codepoint > Char::MAX_CODEPOINT
            codepoint.chr
        rescue
            nil
        end

        private def self.general_category_for(codepoint : Int32) : String
            return "Cn" unless valid_codepoint?(codepoint)
            ensure_general_category_loaded
            @@general_category_ranges.not_nil!.each do |entry|
                category = entry[0]
                ranges = entry[1]
                return category if range_in?(ranges, codepoint)
            end
            "Cn"
        end

        private def self.combining_class_for(codepoint : Int32) : Int32
            return 0 unless valid_codepoint?(codepoint)
            ensure_combining_class_loaded
            ranges = @@combining_class_ranges.not_nil!
            left = 0
            right = ranges.size - 1

            while left <= right
                mid = (left + right) // 2
                low = ranges[mid][0]
                high = ranges[mid][1]

                if codepoint < low
                    right = mid - 1
                elsif codepoint > high
                    left = mid + 1
                else
                    return ranges[mid][2]
                end
            end

            0
        end

        private def self.ensure_general_category_loaded
            return if @@general_category_ranges
            @@general_category_ranges = load_general_category_ranges
        end

        private def self.ensure_combining_class_loaded
            return if @@combining_class_ranges
            @@combining_class_ranges = load_combining_class_ranges
        end

        private def self.load_general_category_ranges : Array(Tuple(String, Array(Tuple(Int32, Int32))))
            categories = {} of String => Array(Tuple(Int32, Int32))
            path = derived_general_category_path

            begin
                File.each_line(path) do |raw|
                    line = raw.split('#', 2)[0].strip
                    next if line.empty?

                    pieces = line.split(';', 2)
                    next unless pieces.size == 2

                    code_field = pieces[0].strip
                    category = pieces[1].strip
                    ranges = categories[category]? || begin
                        fresh_ranges = [] of Tuple(Int32, Int32)
                        categories[category] = fresh_ranges
                        fresh_ranges
                    end

                    if (dots = code_field.index(".."))
                        low = code_field[0, dots].to_i(16)
                        high = code_field[dots + 2, code_field.size - (dots + 2)].to_i(16)
                        ranges << {low, high}
                    else
                        cp = code_field.to_i(16)
                        ranges << {cp, cp}
                    end
                end
            rescue ex : File::NotFoundError
                unless @@warned_missing_general_category
                    @@warned_missing_general_category = true
                    STDERR.puts "WARNING: Missing #{RELATIVE_DERIVED_GENERAL_CATEGORY}; general category lookups will default to Cn."
                end
            end

            categories.keys.sort.map do |key|
                ranges = categories[key]
                ranges.sort_by!(&.[0])
                {key, merge_ranges(ranges)}
            end
        end

        private def self.load_combining_class_ranges : Array(Tuple(Int32, Int32, Int32))
            ranges = [] of Tuple(Int32, Int32, Int32)
            path = derived_combining_class_path

            begin
                File.each_line(path) do |raw|
                    line = raw.split('#', 2)[0].strip
                    next if line.empty?

                    pieces = line.split(';', 2)
                    next unless pieces.size == 2

                    code_field = pieces[0].strip
                    class_val = pieces[1].strip.to_i

                    if (dots = code_field.index(".."))
                        low = code_field[0, dots].to_i(16)
                        high = code_field[dots + 2, code_field.size - (dots + 2)].to_i(16)
                        ranges << {low, high, class_val}
                    else
                        cp = code_field.to_i(16)
                        ranges << {cp, cp, class_val}
                    end
                end
            rescue ex : File::NotFoundError
                unless @@warned_missing_combining_class
                    @@warned_missing_combining_class = true
                    STDERR.puts "WARNING: Missing #{RELATIVE_DERIVED_COMBINING_CLASS}; combining class lookups will default to 0."
                end
            end

            ranges.sort_by!(&.[0])
            ranges
        end

        private def self.range_in?(ranges : Array(Tuple(Int32, Int32)), codepoint : Int32) : Bool
            left = 0
            right = ranges.size - 1

            while left <= right
                mid = (left + right) // 2
                low = ranges[mid][0]
                high = ranges[mid][1]

                if codepoint < low
                    right = mid - 1
                elsif codepoint > high
                    left = mid + 1
                else
                    return true
                end
            end

            false
        end

        private def self.merge_ranges(ranges : Array(Tuple(Int32, Int32))) : Array(Tuple(Int32, Int32))
            return ranges if ranges.empty?

            merged = [] of Tuple(Int32, Int32)
            current_low, current_high = ranges[0]

            i = 1
            while i < ranges.size
                low, high = ranges[i]
                if low <= current_high + 1
                    current_high = high if high > current_high
                else
                    merged << {current_low, current_high}
                    current_low = low
                    current_high = high
                end
                i += 1
            end

            merged << {current_low, current_high}
            merged
        end

        private def self.valid_codepoint?(codepoint : Int32) : Bool
            codepoint >= 0 && codepoint <= Char::MAX_CODEPOINT
        end

        private def self.derived_general_category_path : String
            candidates = [] of String

            if explicit = ENV["DRAGONSTONE_UCD_DERIVED_GENERAL_CATEGORY"]?
                candidates << explicit
            end

            if root = ENV["DRAGONSTONE_ROOT"]?
                candidates << File.join(root, RELATIVE_DERIVED_GENERAL_CATEGORY)
            end

            candidates << File.join(Dir.current, RELATIVE_DERIVED_GENERAL_CATEGORY)

            if exe = Process.executable_path
                exe_dir = File.dirname(exe)
                candidates << File.join(exe_dir, RELATIVE_DERIVED_GENERAL_CATEGORY)
                candidates << File.expand_path(File.join(exe_dir, "..", RELATIVE_DERIVED_GENERAL_CATEGORY))
            end

            candidates.each do |path|
                return path if File.exists?(path)
            end

            RELATIVE_DERIVED_GENERAL_CATEGORY
        end

        private def self.derived_combining_class_path : String
            candidates = [] of String

            if explicit = ENV["DRAGONSTONE_UCD_DERIVED_COMBINING_CLASS"]?
                candidates << explicit
            end

            if root = ENV["DRAGONSTONE_ROOT"]?
                candidates << File.join(root, RELATIVE_DERIVED_COMBINING_CLASS)
            end

            candidates << File.join(Dir.current, RELATIVE_DERIVED_COMBINING_CLASS)

            if exe = Process.executable_path
                exe_dir = File.dirname(exe)
                candidates << File.join(exe_dir, RELATIVE_DERIVED_COMBINING_CLASS)
                candidates << File.expand_path(File.join(exe_dir, "..", RELATIVE_DERIVED_COMBINING_CLASS))
            end

            candidates.each do |path|
                return path if File.exists?(path)
            end

            RELATIVE_DERIVED_COMBINING_CLASS
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

        private def self.abi_string(ptr : UInt8*) : String
            return "" if ptr.null?
            value = String.new(ptr)
            DragonstoneABI.dragonstone_std_free(ptr.as(Void*))
            value
        end

        private def self.abi_path_create(path : String) : String
            ptr = DragonstoneABI.dragonstone_path_create(path)
            abi_string(ptr)
        end

        private def self.abi_path_normalize(path : String) : String
            ptr = DragonstoneABI.dragonstone_path_normalize(path)
            abi_string(ptr)
        end

        private def self.abi_path_parent(path : String) : String
            ptr = DragonstoneABI.dragonstone_path_parent(path)
            abi_string(ptr)
        end

        private def self.abi_path_base(path : String) : String
            ptr = DragonstoneABI.dragonstone_path_base(path)
            abi_string(ptr)
        end

        private def self.abi_path_expand(path : String) : String
            ptr = DragonstoneABI.dragonstone_path_expand(path)
            abi_string(ptr)
        end

        private def self.abi_path_delete(path : String) : String
            ptr = DragonstoneABI.dragonstone_path_delete(path)
            abi_string(ptr)
        end

        private def self.abi_file_exists?(path : String) : Bool
            DragonstoneABI.dragonstone_file_exists(path) != 0
        end

        private def self.abi_file_is_file?(path : String) : Bool
            DragonstoneABI.dragonstone_file_is_file(path) != 0
        end

        private def self.abi_file_size(path : String) : Int64
            DragonstoneABI.dragonstone_file_size(path)
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

    module Host
        
    end
end
