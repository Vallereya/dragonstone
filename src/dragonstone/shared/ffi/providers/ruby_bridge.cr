module Dragonstone
    module FFI
        module Providers
            module RubyBridge
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

                    @@ruby_initialized = false

                    def self.available? : Bool
                        true
                    end

                    def self.ensure_runtime
                        return if @@ruby_initialized

                        status = LibRuby.ruby_setup
                        raise "Failed to initialize embedded Ruby runtime (code #{status})" unless status == 0

                        @@ruby_initialized = true
                    end

                    def self.call(method_name : String, arguments : Array(Dragonstone::FFI::InteropValue)) : Dragonstone::FFI::InteropValue
                        ensure_runtime

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

                    private def self.to_ruby_value(value : Dragonstone::FFI::InteropValue) : LibRuby::VALUE
                        ensure_runtime

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

                    private def self.from_ruby_value(value : LibRuby::VALUE) : Dragonstone::FFI::InteropValue
                        nil
                    end
                {% else %}
                    def self.available? : Bool
                        false
                    end

                    def self.ensure_runtime
                    end

                    def self.call(method_name : String, arguments : Array(Dragonstone::FFI::InteropValue)) : Dragonstone::FFI::InteropValue
                        raise "Ruby FFI is not enabled"
                    end
                {% end %}
            end
        end
    end
end
