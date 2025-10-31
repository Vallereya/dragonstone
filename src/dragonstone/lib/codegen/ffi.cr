require "file_utils"

# ---------------------------------
# -------------- FFI --------------
# ---------------------------------

# Was running into issues using calling ruby so
# all of this basically only allows puts/print 
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

module Dragonstone
    module FFI
        alias InteropValue = Nil | Bool | Int32 | Int64 | Float64 | String | Char | Array(InteropValue)

        RUBY_BRIDGE_ENABLED = {{ env("DRAGONSTONE_RUBY_LIB") ? true : false }}

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

            when "puts"
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

            else
                raise "Unknown Crystal function: #{function_name}"
            end
        end

        def self.call_c(function_name : String, arguments : Array(InteropValue)) : InteropValue
            case function_name

            when "printf"
                format_value = arguments[0]?

                unless format_value.is_a?(String)
                    raise "ffi.call_c('printf', ...) requires the first argument to be a format string"
                end

                LibC.printf(format_value.to_unsafe)
                nil
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
    end
end
