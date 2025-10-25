module Dragonstone
    module OPC
        NOP   = 0

        # Constants / Locals
        CONST           = 1     # [CONST, const_index]                                      -> push consts[const_index]
        LOAD            = 2     # [LOAD,  name_index]                                       -> push env[name_index]
        STORE           = 3     # [STORE, name_index]                                       -> env[name_index] = pop (and push value back)
        POP             = 41    # pop 1

        # Arithmetic
        ADD             = 10
        SUB             = 11
        MUL             = 12
        DIV             = 13

        # Comparisons
        EQ              = 20
        NE              = 21
        LT              = 22
        LE              = 23
        GT              = 24
        GE              = 25

        # Control Flow
        JMP             = 30    # [JMP,  target_index]
        JMPF            = 31    # [JMPF, target_index]                                      -> if pop is falsey, jump

        # IO / Misc
        PUTS            = 40    # [PUTS, argc]                                              -> consume argc items, emit line, push nil
        DEBUG_PRINT     = 52    # [DEBUG_PRINT, const_index]                                -> format top of stack with const string
        TYPEOF          = 53    # TYPEOF                                                    -> replace top of stack with its type name string

        # Composite / Objects
        MAKE_ARRAY      = 55    # [MAKE_ARRAY, count]                                       -> pop count items -> push array
        INDEX           = 56    # INDEX                                                     -> pop index, pop object -> push object[index]
        TO_S            = 57    # TO_S                                                      -> pop value, push value.to_s
        CONCAT          = 58    # CONCAT                                                    -> pop rhs, pop lhs, push lhs + rhs

        # Functions & Calls
        CALL            = 50    # [CALL, argc, name_index]                                  -> call global function
        RET             = 51    # return from function using top-of-stack as result
        INVOKE          = 54    # [INVOKE, name_index, argc]                                -> call method on receiver
        MAKE_FUNCTION   = 59    # [MAKE_FUNCTION, name_index, params_const, chunk_const]    -> push closure

        HALT            = 60    # Terminate Execution
    end
end
