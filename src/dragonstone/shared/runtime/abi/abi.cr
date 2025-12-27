# ----------------------------------
# -------------- ABI ---------------
# - (Application Binary Interface) -
# --- For Stage0 Implementation ----
# ----------------------------------

@[Link("dragonstone_abi")]
lib DragonstoneABI

    # Argument functions.
    fun dragonstone_io_set_argv(argc : Int64, argv : UInt8**) : Void
    fun dragonstone_io_argc : Int64
    fun dragonstone_io_argv : UInt8**

    # Output functions.
    fun dragonstone_io_write_stdout(bytes : UInt8*, len : LibC::SizeT) : Void
    fun dragonstone_io_write_stderr(bytes : UInt8*, len : LibC::SizeT) : Void
    fun dragonstone_io_flush_stdout : Void
    fun dragonstone_io_flush_stderr : Void

    # Input functions.
    fun dragonstone_io_read_stdin_line : UInt8*
    fun dragonstone_io_read_argf : UInt8*

    # Standard memory management functions.
    fun dragonstone_std_free(ptr : Void*) : Void

    # File system functions.
    fun dragonstone_file_exists(path : UInt8*) : Int32
    fun dragonstone_file_is_file(path : UInt8*) : Int32
    fun dragonstone_file_size(path : UInt8*) : Int64
    fun dragonstone_file_read(path : UInt8*) : UInt8*
    fun dragonstone_file_write(path : UInt8*, bytes : UInt8*, len : LibC::SizeT, append : Int32) : Int64
    fun dragonstone_file_delete(path : UInt8*) : Int32

    # Path manipulation functions.
    fun dragonstone_path_create(path : UInt8*) : UInt8*
    fun dragonstone_path_normalize(path : UInt8*) : UInt8*
    fun dragonstone_path_parent(path : UInt8*) : UInt8*
    fun dragonstone_path_base(path : UInt8*) : UInt8*
    fun dragonstone_path_expand(path : UInt8*) : UInt8*
    fun dragonstone_path_delete(path : UInt8*) : UInt8*

    # Garbage Collector functions.
    # Opaque pointer types
    type Area = Void*

    # Initialization
    fun dragonstone_gc_init : Void
    fun dragonstone_gc_shutdown : Void

    # Allocation
    fun dragonstone_gc_alloc(size : LibC::SizeT) : Void*
    fun dragonstone_gc_alloc_atomic(size : LibC::SizeT) : Void*
    fun dragonstone_gc_realloc(ptr : Void*, size : LibC::SizeT) : Void*
    fun dragonstone_gc_memdup(ptr : Void*, size : LibC::SizeT) : Void*

    # Area management
    fun dragonstone_gc_begin_area : Area
    fun dragonstone_gc_begin_area_named(name : LibC::Char*) : Area
    fun dragonstone_gc_end_area(area : Area) : Void
    fun dragonstone_gc_current_area : Area
    fun dragonstone_gc_area_parent(area : Area) : Area
    fun dragonstone_gc_area_name(area : Area) : LibC::Char*
    fun dragonstone_gc_area_count(area : Area) : LibC::SizeT

    # Escape / Promotion
    fun dragonstone_gc_escape(ptr : Void*) : Void*
    fun dragonstone_gc_escape_to(ptr : Void*, target_area : Area) : Void*
    fun dragonstone_gc_copy(ptr : Void*, size : LibC::SizeT) : Void*

    # Enable / Disable
    fun dragonstone_gc_disable : Void
    fun dragonstone_gc_enable : Void
    fun dragonstone_gc_is_enabled : Bool
    fun dragonstone_gc_disable_depth : LibC::Int

    # Collection
    fun dragonstone_gc_collect : Void
    fun dragonstone_gc_collect_if_needed : Void

    # Write barrier
    fun dragonstone_gc_write_barrier(container : Void*, value : Void*) : Void
    fun dragonstone_gc_is_in_area(ptr : Void*, area : Area) : Bool
    fun dragonstone_gc_find_area(ptr : Void*) : Area

    # Debugging
    fun dragonstone_gc_set_verbose(enabled : Bool) : Void
    fun dragonstone_gc_is_verbose : Bool
    fun dragonstone_gc_dump_state : Void
    fun dragonstone_gc_dump_areas : Void
end
