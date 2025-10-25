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
    end
end
