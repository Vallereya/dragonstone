require "../../../language/ast/ast"

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

module Dragonstone
    module Runtime
        module GC
            enum GarbageMode
                Disabled
                Enabled
                Area
            end

            enum OwnershipMode
                Disabled
                Enabled
            end

            record Flags,
                garbage : GarbageMode = GarbageMode::Enabled,
                ownership : OwnershipMode = OwnershipMode::Enabled,
                area_name : String? = nil,
                escape_return : Bool = false

            def self.flags_from_annotations(annotations : Array(AST::Annotation)) : Flags
                garbage = GarbageMode::Enabled      # Default: enabled
                ownership = OwnershipMode::Enabled  # Default: enabled
                area_name : String? = nil
                escape_return = false

                annotations.each do |ann|
                    case ann.name
                        
                    when "gc.disable"
                        garbage = GarbageMode::Disabled
                    when "gc.enable"
                        garbage = GarbageMode::Enabled
                    when "gc.area"
                        garbage = GarbageMode::Area
                    when "Garbage"
                        case ann.value
                        
                        when "enable"
                            garbage = GarbageMode::Enabled
                        when "disable"
                            garbage = GarbageMode::Disabled
                        when "area"
                            garbage = GarbageMode::Area
                        end

                        if area_arg = ann.named_args["area"]?
                            garbage = GarbageMode::Area
                            area_name = area_arg.as_s if area_arg.responds_to?(:as_s)
                        end

                        if escape_arg = ann.named_args["escape"]?
                            escape_return = escape_arg.to_s == "return"
                        end
                    when "Ownership"
                        case ann.value

                        when "enable"
                            ownership = OwnershipMode::Enabled
                        when "disable"
                            ownership = OwnershipMode::Disabled
                        end
                    end
                end

                Flags.new(garbage, ownership, area_name, escape_return)
            end

            @@initialized = false

            def self.init : Nil
                return if @@initialized
                LibDragonstoneGC.dragonstone_gc_init
                @@initialized = true
            end

            def self.shutdown : Nil
                return unless @@initialized
                LibDragonstoneGC.dragonstone_gc_shutdown
                @@initialized = false
            end

            def self.initialized? : Bool
                @@initialized
            end

            def self.alloc(size : Int) : Pointer(Void)
                init unless @@initialized
                LibDragonstoneGC.dragonstone_gc_alloc(size)
            end

            def self.alloc_atomic(size : Int) : Pointer(Void)
                init unless @@initialized
                LibDragonstoneGC.dragonstone_gc_alloc_atomic(size)
            end

            struct Area
                getter handle : LibDragonstoneGC::Area

                def initialize(@handle : LibDragonstoneGC::Area)

                end

                def parent : Area?
                    parent_handle = LibDragonstoneGC.dragonstone_gc_area_parent(@handle)
                    parent_handle.null? ? nil : Area.new(parent_handle)
                end

                def name : String?
                    name_ptr = LibDragonstoneGC.dragonstone_gc_area_name(@handle)
                    name_ptr.null? ? nil : String.new(name_ptr)
                end

                def count : UInt64
                    LibDragonstoneGC.dragonstone_gc_area_count(@handle)
                end

                def null? : Bool
                    @handle.null?
                end
            end

            def self.begin_area(name : String? = nil) : Area
                init unless @@initialized

                handle = if name
                    LibDragonstoneGC.dragonstone_gc_begin_area_named(name.to_unsafe)
                else
                    LibDragonstoneGC.dragonstone_gc_begin_area
                end
                Area.new(handle)
            end

            def self.end_area(area : Area) : Nil
                LibDragonstoneGC.dragonstone_gc_end_area(area.handle)
            end

            def self.current_area : Area?
                handle = LibDragonstoneGC.dragonstone_gc_current_area
                handle.null? ? nil : Area.new(handle)
            end

            def self.with_area(name : String? = nil, &)
                area = begin_area(name)
                
                begin
                    yield area
                ensure
                    end_area(area)
                end
            end

            def self.escape(ptr : Pointer(Void)) : Pointer(Void)
                LibDragonstoneGC.dragonstone_gc_escape(ptr)
            end

            def self.escape_to(ptr : Pointer(Void), target_area : Area?) : Pointer(Void)
                target_handle = target_area.try(&.handle) || Pointer(Void).null
                LibDragonstoneGC.dragonstone_gc_escape_to(ptr, target_handle)
            end

            def self.disable : Nil
                init unless @@initialized
                LibDragonstoneGC.dragonstone_gc_disable
            end

            def self.enable : Nil
                LibDragonstoneGC.dragonstone_gc_enable
            end

            def self.enabled? : Bool
                LibDragonstoneGC.dragonstone_gc_is_enabled
            end

            def self.disable_depth : Int32
                LibDragonstoneGC.dragonstone_gc_disable_depth
            end

            def self.with_disabled(&)
                disable

                begin
                    yield
                ensure
                    enable
                end
            end

            def self.collect : Nil
                LibDragonstoneGC.dragonstone_gc_collect
            end

            def self.collect_if_needed : Nil
                LibDragonstoneGC.dragonstone_gc_collect_if_needed
            end

            def self.write_barrier(container : Pointer(Void), value : Pointer(Void)) : Nil
                LibDragonstoneGC.dragonstone_gc_write_barrier(container, value)
            end

            def self.in_area?(ptr : Pointer(Void), area : Area?) : Bool
                area_handle = area.try(&.handle) || Pointer(Void).null
                LibDragonstoneGC.dragonstone_gc_is_in_area(ptr, area_handle)
            end

            def self.find_area(ptr : Pointer(Void)) : Area?
                handle = LibDragonstoneGC.dragonstone_gc_find_area(ptr)
                handle.null? ? nil : Area.new(handle)
            end

            def self.verbose=(enabled : Bool) : Nil
                LibDragonstoneGC.dragonstone_gc_set_verbose(enabled)
            end

            def self.verbose? : Bool
                LibDragonstoneGC.dragonstone_gc_is_verbose
            end

            def self.dump_state : Nil
                LibDragonstoneGC.dragonstone_gc_dump_state
            end

            def self.dump_areas : Nil
                LibDragonstoneGC.dragonstone_gc_dump_areas
            end

            class Manager(T)
                getter copy_proc : Proc(T, T)

                def initialize(
                        @copy_proc : Proc(T, T),
                        @on_first_disable : Proc(Nil)? = nil,
                        @on_last_enable : Proc(Nil)? = nil
                    )

                    GC.init
                end

                def disable_depth : Int32
                    GC.disable_depth
                end

                def disable : Nil
                    was_enabled = GC.enabled?
                    GC.disable

                    if was_enabled && !GC.enabled?
                        @on_first_disable.try &.call
                    end
                end

                def enable : Nil
                    was_disabled = !GC.enabled?
                    GC.enable

                    if was_disabled && GC.enabled?
                        @on_last_enable.try &.call
                    end
                end

                def with_disabled(&)
                    GC.with_disabled { yield }
                end

                def begin_area(name : String? = nil) : Area
                    GC.begin_area(name)
                end

                def end_area(area : Area? = nil) : Nil
                    target = area || GC.current_area
                    GC.end_area(target) if target
                end

                def with_area(name : String? = nil, &)
                    GC.with_area(name) { |area| yield area }
                end

                def current_area : Area?
                    GC.current_area
                end

                def copy(value : T) : T
                    @copy_proc.call(value)
                end
            end
        end
    end
end
