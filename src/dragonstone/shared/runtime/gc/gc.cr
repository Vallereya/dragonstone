require "../../language/ast/ast"

module Dragonstone
    module Runtime
        module GC
            record Flags,
                disable : Bool = false,
                area : Bool = false

            def self.flags_from_annotations(annotations : Array(AST::Annotation)) : Flags
                disable = false
                area = false

                annotations.each do |ann|
                    case ann.name
                    when "gc.disable"
                        disable = true
                    when "gc.area"
                        area = true
                    end
                end

                Flags.new(disable, area)
            end

            class Area(T)
                getter allocations : Array(T)

                def initialize
                    @allocations = [] of T
                    @finalizers = [] of Proc(Nil)
                end

                def track(value : T) : T
                    @allocations << value
                    value
                end

                def on_finalize(&block : -> Nil) : Nil
                    @finalizers << block
                end

                def clear : Nil
                    @allocations.clear
                    @finalizers.each { |finalizer| finalizer.call }
                    @finalizers.clear
                end
            end

            class Manager(T)
                getter disable_depth : Int32

                def initialize(
                    @copy_proc : Proc(T, T),
                    @on_first_disable : Proc(Nil)? = nil,
                    @on_last_enable : Proc(Nil)? = nil
                )
                    @disable_depth = 0
                    @area_stack = [] of Area(T)
                end

                def disable : Nil
                    @disable_depth += 1
                    if @disable_depth == 1
                        @on_first_disable.try &.call
                    end
                end

                def enable : Nil
                    return if @disable_depth == 0
                    @disable_depth -= 1
                    if @disable_depth == 0
                        @on_last_enable.try &.call
                    end
                end

                def with_disabled
                    disable
                    yield
                ensure
                    enable
                end

                def begin_area : Area(T)
                    area = Area(T).new
                    @area_stack << area
                    area
                end

                def end_area(area : Area(T)? = nil) : Nil
                    target = area || @area_stack.pop?
                    return unless target

                    if area
                        @area_stack.delete(area)
                    end

                    target.clear
                end

                def with_area
                    area = begin_area
                    yield area
                ensure
                    end_area(area)
                end

                def current_area : Area(T)?
                    @area_stack.last?
                end

                def copy(value : T) : T
                    @copy_proc.call(value)
                end
            end
        end
    end
end
