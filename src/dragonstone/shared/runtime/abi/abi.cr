# ----------------------------------
# -------------- ABI ---------------
# - (Application Binary Interface) -
# --- For Stage0 Implementation ----
# ----------------------------------

@[Link("dragonstone_abi")]
lib DragonstoneABI
    fun dragonstone_io_set_argv(argc : Int64, argv : UInt8**) : Void
    fun dragonstone_io_argc : Int64
    fun dragonstone_io_argv : UInt8**

    fun dragonstone_io_write_stdout(bytes : UInt8*, len : LibC::SizeT) : Void
    fun dragonstone_io_write_stderr(bytes : UInt8*, len : LibC::SizeT) : Void
    fun dragonstone_io_flush_stdout : Void
    fun dragonstone_io_flush_stderr : Void

    fun dragonstone_io_read_stdin_line : UInt8*
    fun dragonstone_io_read_argf : UInt8*

    fun dragonstone_std_free(ptr : Void*) : Void

    fun dragonstone_file_exists(path : UInt8*) : Int32
    fun dragonstone_file_is_file(path : UInt8*) : Int32
    fun dragonstone_file_size(path : UInt8*) : Int64
    fun dragonstone_file_read(path : UInt8*) : UInt8*
    fun dragonstone_file_write(path : UInt8*, bytes : UInt8*, len : LibC::SizeT, append : Int32) : Int64
    fun dragonstone_file_delete(path : UInt8*) : Int32

    fun dragonstone_path_create(path : UInt8*) : UInt8*
    fun dragonstone_path_normalize(path : UInt8*) : UInt8*
    fun dragonstone_path_parent(path : UInt8*) : UInt8*
    fun dragonstone_path_base(path : UInt8*) : UInt8*
    fun dragonstone_path_expand(path : UInt8*) : UInt8*
    fun dragonstone_path_delete(path : UInt8*) : UInt8*
end
