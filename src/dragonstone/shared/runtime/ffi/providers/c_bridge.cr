module Dragonstone
    module FFI
        module Providers
            module CBridge
                extend Dragonstone::FFI::Utils

                lib DragonstoneLibC
                    fun getchar : Int32
                end

                lib LibM
                    fun floor(value : Float64) : Float64
                    fun ceil(value : Float64) : Float64
                    fun round(value : Float64) : Float64
                    fun trunc(value : Float64) : Float64
                end

                def self.call(function_name : String, arguments : Array(Dragonstone::FFI::InteropValue)) : Dragonstone::FFI::InteropValue
                    case function_name
                    when "printf"
                        format_value = expect_string(arguments, 0, function_name)
                        ::LibC.printf(format_value)
                    when "getchar"
                        DragonstoneLibC.getchar
                    when "write"
                        fd = expect_int(arguments, 0, function_name)
                        content = expect_string(arguments, 1, function_name)
                        count = if arguments.size >= 3
                            expect_int(arguments, 2, function_name)
                        else
                            content.bytesize
                        end
                        buf = content.to_unsafe

                        {% if flag?(:windows) %}
                            ::LibC._write(fd, buf, count.to_u32).to_i64
                        {% else %}
                            capped = Math.min(count, content.bytesize)
                            {% if flag?(:bits32) %}
                                ::LibC.write(fd.to_i, buf.as(Void*), capped.to_u32).to_i64
                            {% else %}
                                ::LibC.write(fd.to_i, buf.as(Void*), capped.to_u64).to_i64
                            {% end %}
                        {% end %}
                    when "chr"
                        code = expect_int(arguments, 0, function_name)
                        code.chr
                    when "floor"
                        value = arguments[0]
                        case value
                        when Float64
                            LibM.floor(value)
                        when Float32
                            LibM.floor(value.to_f64)
                        when Int32, Int64
                            value.to_f64
                        else
                            raise "floor requires a numeric argument"
                        end
                    when "ceil"
                        value = arguments[0]
                        case value
                        when Float64
                            LibM.ceil(value)
                        when Float32
                            LibM.ceil(value.to_f64)
                        when Int32, Int64
                            value.to_f64
                        else
                            raise "ceil requires a numeric argument"
                        end
                    when "round"
                        value = arguments[0]
                        case value
                        when Float64
                            LibM.round(value)
                        when Float32
                            LibM.round(value.to_f64)
                        when Int32, Int64
                            value.to_f64
                        else
                            raise "round requires a numeric argument"
                        end
                    when "trunc"
                        value = arguments[0]
                        case value
                        when Float64
                            LibM.trunc(value)
                        when Float32
                            LibM.trunc(value.to_f64)
                        when Int32, Int64
                            value.to_f64
                        else
                            raise "trunc requires a numeric argument"
                        end
                    when "fsync"
                        fd = expect_int(arguments, 0, function_name)
                        {% if flag?(:windows) %}
                            ::LibC._commit(fd)
                        {% else %}
                            ::LibC.fsync(fd)
                        {% end %}
                    else
                        raise "Unknown C function: #{function_name}"
                    end
                end
            end
        end
    end
end
