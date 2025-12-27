require "../../../../language/ast/ast"
require "../../abi"

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
                escape_return : Bool = false,
                operator : AST::Annotation::MemoryOperator? = nil

            struct Flags
                def gc_disabled? : Bool
                    garbage == GarbageMode::Disabled
                end

                def gc_enabled? : Bool
                    garbage == GarbageMode::Enabled || garbage == GarbageMode::Area
                end

                def gc_area? : Bool
                    garbage == GarbageMode::Area
                end

                def ownership_enabled? : Bool
                    ownership == OwnershipMode::Enabled
                end

                def effective_garbage : GarbageMode
                    case operator
                    when AST::Annotation::MemoryOperator::Or
                        if ownership == OwnershipMode::Enabled && garbage == GarbageMode::Disabled
                            return GarbageMode::Enabled
                        end
                    end
                    garbage
                end

                def effective_gc_disabled? : Bool
                    effective_garbage == GarbageMode::Disabled
                end

                def effective_gc_area? : Bool
                    effective_garbage == GarbageMode::Area
                end

                def effective_area_name : String?
                    effective_gc_area? ? area_name : nil
                end
            end

            def self.flags_from_annotations(annotations : Array(AST::Annotation)) : Flags
                garbage = GarbageMode::Enabled
                ownership = OwnershipMode::Enabled
                area_name : String? = nil
                escape_return = false
                operator : AST::Annotation::MemoryOperator? = nil

                annotations.each do |ann|
                    if memory = ann.memory
                        if garbage_mode = memory.garbage
                            garbage = case garbage_mode
                                      when AST::Annotation::MemoryAnnotation::GarbageMode::Disable then GarbageMode::Disabled
                                      when AST::Annotation::MemoryAnnotation::GarbageMode::Area then GarbageMode::Area
                                      when AST::Annotation::MemoryAnnotation::GarbageMode::Enable then GarbageMode::Enabled
                                      else
                                          garbage
                                      end
                        end
                        if ownership_mode = memory.ownership
                            ownership = case ownership_mode
                                        when AST::Annotation::MemoryAnnotation::OwnershipMode::Disable then OwnershipMode::Disabled
                                        when AST::Annotation::MemoryAnnotation::OwnershipMode::Enable then OwnershipMode::Enabled
                                        else
                                            ownership
                                        end
                        end
                        area_name = memory.area_name if memory.area_name
                        escape_return = memory.escape_return if memory.escape_return
                        operator = memory.operator if memory.operator
                        next
                    end

                    case ann.name
                    when "gc.disable"
                        garbage = GarbageMode::Disabled
                    when "gc.enable"
                        garbage = GarbageMode::Enabled
                    when "gc.area"
                        garbage = GarbageMode::Area
                    when "Garbage"
                        garbage_arg = ann.arguments.first?
                        if garbage_arg
                            case garbage_arg.to_source
                            when "enable"
                                garbage = GarbageMode::Enabled
                            when "disable"
                                garbage = GarbageMode::Disabled
                            when "area"
                                garbage = GarbageMode::Area
                            end
                        end
                    when "Ownership"
                        ownership_arg = ann.arguments.first?
                        if ownership_arg
                            case ownership_arg.to_source
                            when "enable"
                                ownership = OwnershipMode::Enabled
                            when "disable"
                                ownership = OwnershipMode::Disabled
                            end
                        end
                    end
                end

                Flags.new(garbage, ownership, area_name, escape_return, operator)
            end

            @@initialized = false

            def self.init : Nil
                return if @@initialized
                DragonstoneABI.dragonstone_gc_init
                @@initialized = true
            end

            def self.shutdown : Nil
                return unless @@initialized
                DragonstoneABI.dragonstone_gc_shutdown
                @@initialized = false
            end

            def self.initialized? : Bool
                @@initialized
            end

            def self.alloc(size : Int) : Pointer(Void)
                init unless @@initialized
                DragonstoneABI.dragonstone_gc_alloc(size)
            end

            def self.alloc_atomic(size : Int) : Pointer(Void)
                init unless @@initialized
                DragonstoneABI.dragonstone_gc_alloc_atomic(size)
            end

            struct Area
                getter handle : DragonstoneABI::Area

                def initialize(@handle : DragonstoneABI::Area)
                end

                def parent : Area?
                    parent_handle = DragonstoneABI.dragonstone_gc_area_parent(@handle)
                    parent_handle.null? ? nil : Area.new(parent_handle)
                end

                def name : String?
                    name_ptr = DragonstoneABI.dragonstone_gc_area_name(@handle)
                    name_ptr.null? ? nil : String.new(name_ptr)
                end

                def count : UInt64
                    DragonstoneABI.dragonstone_gc_area_count(@handle)
                end

                def null? : Bool
                    @handle.null?
                end
            end

            def self.begin_area(name : String? = nil) : Area
                init unless @@initialized
                handle = if name
                    DragonstoneABI.dragonstone_gc_begin_area_named(name.to_unsafe)
                else
                    DragonstoneABI.dragonstone_gc_begin_area
                end
                Area.new(handle)
            end

            def self.end_area(area : Area) : Nil
                DragonstoneABI.dragonstone_gc_end_area(area.handle)
            end

            def self.current_area : Area?
                handle = DragonstoneABI.dragonstone_gc_current_area
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
                escape_ptr(ptr)
            end

            def self.escape_to(ptr : Pointer(Void), target_area : Area?) : Pointer(Void)
                escape_ptr_to(ptr, target_area)
            end

            def self.escape_ptr(ptr : Pointer(Void)) : Pointer(Void)
                DragonstoneABI.dragonstone_gc_escape(ptr)
            end

            def self.escape_ptr_to(ptr : Pointer(Void), target_area : Area?) : Pointer(Void)
                target_handle = target_area.try(&.handle) || Pointer(Void).null
                DragonstoneABI.dragonstone_gc_escape_to(ptr, target_handle)
            end

            def self.escape(value : ::Dragonstone::RuntimeValue) : ::Dragonstone::RuntimeValue
                deep_copy_runtime(value)
            end

            def self.escape_to(value : ::Dragonstone::RuntimeValue, _target_area : Area?) : ::Dragonstone::RuntimeValue
                deep_copy_runtime(value)
            end

            def self.copy(value : ::Dragonstone::RuntimeValue) : ::Dragonstone::RuntimeValue
                deep_copy_runtime(value)
            end

            def self.escape(value : ::Dragonstone::Bytecode::Value) : ::Dragonstone::Bytecode::Value
                deep_copy_bytecode(value)
            end

            def self.escape_to(value : ::Dragonstone::Bytecode::Value, _target_area : Area?) : ::Dragonstone::Bytecode::Value
                deep_copy_bytecode(value)
            end

            def self.copy(value : ::Dragonstone::Bytecode::Value) : ::Dragonstone::Bytecode::Value
                deep_copy_bytecode(value)
            end

            def self.disable : Nil
                init unless @@initialized
                DragonstoneABI.dragonstone_gc_disable
            end

            def self.enable : Nil
                DragonstoneABI.dragonstone_gc_enable
            end

            def self.enabled? : Bool
                DragonstoneABI.dragonstone_gc_is_enabled
            end

            def self.disable_depth : Int32
                DragonstoneABI.dragonstone_gc_disable_depth
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
                DragonstoneABI.dragonstone_gc_collect
            end

            def self.collect_if_needed : Nil
                DragonstoneABI.dragonstone_gc_collect_if_needed
            end

            def self.write_barrier(container : Pointer(Void), value : Pointer(Void)) : Nil
                DragonstoneABI.dragonstone_gc_write_barrier(container, value)
            end

            def self.in_area?(ptr : Pointer(Void), area : Area?) : Bool
                area_handle = area.try(&.handle) || Pointer(Void).null
                DragonstoneABI.dragonstone_gc_is_in_area(ptr, area_handle)
            end

            def self.find_area(ptr : Pointer(Void)) : Area?
                handle = DragonstoneABI.dragonstone_gc_find_area(ptr)
                handle.null? ? nil : Area.new(handle)
            end

            def self.verbose=(enabled : Bool) : Nil
                DragonstoneABI.dragonstone_gc_set_verbose(enabled)
            end

            def self.verbose? : Bool
                DragonstoneABI.dragonstone_gc_is_verbose
            end

            def self.dump_state : Nil
                DragonstoneABI.dragonstone_gc_dump_state
            end

            def self.dump_areas : Nil
                DragonstoneABI.dragonstone_gc_dump_areas
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
