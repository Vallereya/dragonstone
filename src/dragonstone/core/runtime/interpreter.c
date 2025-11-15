#include "dragonstone/core/runtime.h"
#include <stdio.h>

/*

Dragonstone built-in functions that call into C/Ruby/Crystal.

*/
// Example: Dragonstone's `ffi.call_ruby` built-in.
VALUE ds_builtin_ffi_ruby(VALUE self, VALUE receiver, VALUE method, VALUE args) {
    Check_Type(method, T_STRING);
    Check_Type(args, T_ARRAY);
    
    const char* method_name = StringValueCStr(method);
    int argc = RARRAY_LEN(args);
    VALUE* argv = RARRAY_PTR(args);
    
    return ds_ffi_call_ruby(receiver, method_name, argc, argv);
}

// Example: Dragonstone's `ffi.call_c` built-in.
VALUE ds_builtin_ffi_c(VALUE self, VALUE func_name, VALUE args) {
    Check_Type(func_name, T_STRING);
    Check_Type(args, T_ARRAY);
    
    const char* func = StringValueCStr(func_name);
    int argc = RARRAY_LEN(args);
    VALUE* argv = RARRAY_PTR(args);
    
    return ds_ffi_call_c(func, argc, argv);
}

// Example: Dragonstone's `ffi.call_crystal` built-in.
VALUE ds_builtin_ffi_crystal(VALUE self, VALUE func_name, VALUE args) {
    Check_Type(func_name, T_STRING);
    Check_Type(args, T_ARRAY);
    
    const char* func = StringValueCStr(func_name);
    int argc = RARRAY_LEN(args);
    VALUE* argv = RARRAY_PTR(args);
    
    return ds_ffi_call_crystal(func, argc, argv);
}

// Register Dragonstone built-ins.
void ds_init_ffi_builtins(void) {
    VALUE ds_ffi_module = rb_define_module_under(rb_cObject, "FFI");
    
    rb_define_module_function(ds_ffi_module, "call_ruby", ds_builtin_ffi_ruby, 3);

    rb_define_module_function(ds_ffi_module, "call_c", ds_builtin_ffi_c, 2);

    rb_define_module_function(ds_ffi_module, "call_crystal", ds_builtin_ffi_crystal, 2);
}

// Ruby-visible class Dragonstone::Core::Interpreter
static VALUE mDragonstone;
static VALUE mCore;
static VALUE cInterpreter;

// FFI module.
static VALUE mFFI;

// Interpreter state stored in a Ruby object.
typedef struct {
    VALUE scopes;
    VALUE output;
    VALUE log_to_stdout;
    VALUE ruby_interpreter;
} ds_interp_t;

static void ds_interp_free(void *p) {
    xfree(p);
}

static size_t ds_interp_size(const void *p) {
    (void)p;
    return sizeof(ds_interp_t);
}

static void ds_interp_mark(void *p) {
    ds_interp_t *st = (ds_interp_t *)p;

    if (!st) return;
    
    rb_gc_mark(st->scopes);
    rb_gc_mark(st->output);
    rb_gc_mark(st->log_to_stdout);
    rb_gc_mark(st->ruby_interpreter);
}

static const rb_data_type_t ds_interp_type = {
    "Dragonstone::Core::Interpreter",
    { ds_interp_mark, ds_interp_free, ds_interp_size, },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE ds_interp_alloc(VALUE klass) {
    ds_interp_t *st = ALLOC(ds_interp_t);

    st->scopes = Qnil;
    st->output = Qnil;
    st->log_to_stdout = Qfalse;
    st->ruby_interpreter = Qnil;

    return TypedData_Wrap_Struct(klass, &ds_interp_type, st);
}

static VALUE ds_interp_initialize(int argc, VALUE *argv, VALUE self) {
    ds_interp_t *st;

    TypedData_Get_Struct(self, ds_interp_t, &ds_interp_type, st);

    VALUE opts = Qnil;

    ID kw_table[1]; VALUE kw_values[1];

    kw_table[0] = rb_intern("log_to_stdout");

    kw_values[0] = Qfalse;

    rb_scan_args_kw(RB_SCAN_ARGS_KEYWORDS, argc, argv, "00:", &opts);

    if (!NIL_P(opts)) {
        rb_get_kwargs(opts, kw_table, 0, 1, kw_values);
    }

    st->log_to_stdout = RTEST(kw_values[0]) ? Qtrue : Qfalse;

    st->scopes = rb_ary_new();

    rb_ary_push(st->scopes, rb_hash_new());

    st->output = rb_str_new("", 0);

    VALUE interpreter_class = rb_const_get(mDragonstone, rb_intern("Interpreter"));
    VALUE ruby_interp = rb_class_new_instance(0, NULL, interpreter_class);

    if (st->log_to_stdout == Qtrue) {
        rb_iv_set(ruby_interp, "@log_to_stdout", Qtrue);
    }

    st->ruby_interpreter = ruby_interp;

    return self;
}

/*

Looks like shit but cached symbols/IDs from Ruby 
for performance and to avoid repeated rb_intern,
was taking forever to call.

*/
static VALUE sym_statements, sym_name, sym_receiver, sym_arguments;
static VALUE sym_value, sym_left, sym_right, sym_operator;
static VALUE sym_condition, sym_then_block, sym_elsif_blocks, sym_else_block;
static VALUE sym_elements, sym_object, sym_index;
static VALUE sym_body, sym_parameters, sym_block, sym_parts;
static VALUE sym_expression;

static ID id_echo;
static ID id_legacy_puts;
static ID id_kernel_puts;
static ID id_typeof;
static ID id_length, id_size, id_upcase, id_downcase, id_reverse;
static ID id_empty, id_empty_q, id_to_f, id_dup;
static ID id_to_s, id_inspect, id_to_source, id_message;
static ID id_tokenize, id_parse, id_parse_expression_entry;
static ID id_value_method;
static ID id_op_plus, id_op_minus, id_op_multiply, id_op_divide;
static ID id_op_equals, id_op_not_equals, id_op_less, id_op_less_equal;
static ID id_op_greater, id_op_greater_equal;
static ID id_method_plus, id_method_minus, id_method_multiply, id_method_divide;
static ID id_method_equals, id_method_not_equals, id_method_less, id_method_less_equal;
static ID id_method_greater, id_method_greater_equal;
static ID id_push, id_pop, id_first, id_last;
static ID id_part_string;

static VALUE cReturnValue;
static VALUE cLexer, cParser;
static VALUE cInterpreterError, cLexerError, cParserError;

static ID id_fn_kind, id_fn_name, id_fn_params, id_fn_body, id_fn_closure;

/*

Helper functions.

*/

static const char *ds_classname(VALUE obj) {
    return rb_obj_classname(obj);
}

static VALUE ds_current_scope(ds_interp_t *st) {
    long len = RARRAY_LEN(st->scopes);
    return rb_ary_entry(st->scopes, len - 1);
}

static VALUE ds_lookup(ds_interp_t *st, VALUE name_sym) {
    for (long i = RARRAY_LEN(st->scopes) - 1; i >= 0; --i) {

        VALUE scope = rb_ary_entry(st->scopes, i);
        VALUE val = rb_hash_lookup2(scope, name_sym, Qundef);

        if (val != Qundef) {
            return val;
        }
    }

    rb_raise(cInterpreterError, "Undefined variable: %s", rb_id2name(SYM2ID(name_sym)));

    return Qnil;
}

static void ds_set(ds_interp_t *st, VALUE name_sym, VALUE val) {
    VALUE scope = ds_current_scope(st);

    rb_hash_aset(scope, name_sym, val);
}

static void ds_append_output(ds_interp_t *st, VALUE text) {
    VALUE str = rb_String(text);

    rb_str_cat(st->output, RSTRING_PTR(str), RSTRING_LEN(str));
    rb_str_cat2(st->output, "\n");

    if (st->log_to_stdout == Qtrue) {
        rb_funcall(rb_mKernel, id_kernel_puts, 1, str);
    }
}

static int ds_is_truthy(VALUE v) {
    return !(v == Qfalse || v == Qnil);
}

static VALUE ds_format_value(ds_interp_t *st, VALUE value) {
    (void)st;

    if (RB_TYPE_P(value, T_STRING)) {
        return rb_funcall(value, id_inspect, 0);
    }

    if (value == Qnil) {
        return rb_str_new_cstr("nil");
    }

    if (value == Qtrue) {
        return rb_str_new_cstr("true");
    }

    if (value == Qfalse) {
        return rb_str_new_cstr("false");
    }

    if (RB_TYPE_P(value, T_ARRAY)) {
        long len = RARRAY_LEN(value);

        VALUE formatted = rb_ary_new2(len);

        for (long i = 0; i < len; ++i) {
            VALUE elem = rb_ary_entry(value, i);
            VALUE part = ds_format_value(st, elem);
            rb_ary_store(formatted, i, part);
        }

        VALUE result = rb_str_new_cstr("[");
        if (len > 0) {
            VALUE joined = rb_ary_join(formatted, rb_str_new_cstr(", "));
            rb_str_cat(result, RSTRING_PTR(joined), RSTRING_LEN(joined));
        }

        rb_str_cat2(result, "]");
        return result;
    }

    return rb_funcall(value, id_to_s, 0);
}

static VALUE ds_num_coerce(VALUE v) {
    if (RB_INTEGER_TYPE_P(v) || RB_FLOAT_TYPE_P(v)) {
        return v;
    }

    if (rb_respond_to(v, id_to_f)) {
        return rb_funcall(v, id_to_f, 0);
    }

    rb_raise(cInterpreterError, "Non-numeric value in arithmetic");

    return Qnil;
}

static VALUE ds_visit(ds_interp_t *st, VALUE node);

/*

Visitor implementations.

*/

static VALUE ds_visit_program(ds_interp_t *st, VALUE node) {
    VALUE stmts = rb_funcall(node, SYM2ID(sym_statements), 0);
    long count = RARRAY_LEN(stmts);

    for (long i = 0; i < count; ++i) {
        VALUE stmt = rb_ary_entry(stmts, i);
        ds_visit(st, stmt);
    }

    return Qnil;
}

static VALUE ds_visit_literal(ds_interp_t *st, VALUE node) {
    (void)st;

    return rb_funcall(node, SYM2ID(sym_value), 0);
}

static VALUE ds_visit_variable(ds_interp_t *st, VALUE node) {
    VALUE name = rb_funcall(node, SYM2ID(sym_name), 0);
    VALUE sym = RB_TYPE_P(name, T_SYMBOL) ? name : rb_str_intern(name);

    return ds_lookup(st, sym);
}

static VALUE ds_visit_assignment(ds_interp_t *st, VALUE node) {
    VALUE name = rb_funcall(node, SYM2ID(sym_name), 0);
    VALUE sym = RB_TYPE_P(name, T_SYMBOL) ? name : rb_str_intern(name);
    VALUE val_node = rb_funcall(node, SYM2ID(sym_value), 0);
    VALUE val = ds_visit(st, val_node);

    ds_set(st, sym, val);

    return val;
}

static VALUE ds_visit_binary(ds_interp_t *st, VALUE node) {
    VALUE left = ds_visit(st, rb_funcall(node, SYM2ID(sym_left), 0));
    VALUE right = ds_visit(st, rb_funcall(node, SYM2ID(sym_right), 0));
    VALUE op = rb_funcall(node, SYM2ID(sym_operator), 0);

    ID op_id = SYM2ID(op);

    if (op_id == id_op_plus) {

        if (RB_TYPE_P(left, T_STRING) || RB_TYPE_P(right, T_STRING)) {
            return rb_str_plus(rb_String(left), rb_String(right));
        }

        left = ds_num_coerce(left);
        right = ds_num_coerce(right);
        return rb_funcall(left, id_method_plus, 1, right);
    }

    if (op_id == id_op_minus) {
        left = ds_num_coerce(left);
        right = ds_num_coerce(right);
        return rb_funcall(left, id_method_minus, 1, right);
    }

    if (op_id == id_op_multiply) {
        left = ds_num_coerce(left);
        right = ds_num_coerce(right);
        return rb_funcall(left, id_method_multiply, 1, right);
    }

    if (op_id == id_op_divide) {
        left = ds_num_coerce(left);
        right = ds_num_coerce(right);
        return rb_funcall(left, id_method_divide, 1, right);
    }

    if (op_id == id_op_equals) {
        return rb_funcall(left, id_method_equals, 1, right);
    }

    if (op_id == id_op_not_equals) {
        return rb_funcall(left, id_method_not_equals, 1, right);
    }

    if (op_id == id_op_less) {
        return rb_funcall(left, id_method_less, 1, right);
    }

    if (op_id == id_op_less_equal) {
        return rb_funcall(left, id_method_less_equal, 1, right);
    }

    if (op_id == id_op_greater) {
        return rb_funcall(left, id_method_greater, 1, right);
    }

    if (op_id == id_op_greater_equal) {
        return rb_funcall(left, id_method_greater_equal, 1, right);
    }

    rb_raise(cInterpreterError, "Unknown operator");

    return Qnil;
}

static VALUE ds_visit_array_literal(ds_interp_t *st, VALUE node) {
    VALUE elems = rb_funcall(node, SYM2ID(sym_elements), 0);
    
    long len = RARRAY_LEN(elems);

    VALUE arr = rb_ary_new2(len);

    for (long i = 0; i < len; ++i) {
        VALUE elem_node = rb_ary_entry(elems, i);
        VALUE val = ds_visit(st, elem_node);
        rb_ary_store(arr, i, val);
    }

    return arr;
}

static VALUE ds_visit_index_access(ds_interp_t *st, VALUE node) {
    VALUE object = ds_visit(st, rb_funcall(node, SYM2ID(sym_object), 0));
    VALUE index = ds_visit(st, rb_funcall(node, SYM2ID(sym_index), 0));

    return rb_funcall(object, rb_intern("[]"), 1, index);
}

struct ds_interp_eval_ctx {
    ds_interp_t *st;
    VALUE content;
};

static VALUE ds_eval_interpolation_inner(VALUE arg) {
    struct ds_interp_eval_ctx *ctx = (struct ds_interp_eval_ctx *)arg;
    VALUE args[1] = { ctx->content };
    VALUE lexer = rb_class_new_instance(1, args, cLexer);
    VALUE tokens = rb_funcall(lexer, id_tokenize, 0);

    VALUE pargs[1] = { tokens };
    VALUE parser = rb_class_new_instance(1, pargs, cParser);
    VALUE expr = rb_funcall(parser, id_parse_expression_entry, 0);

    return ds_visit(ctx->st, expr);
}

static VALUE ds_eval_interpolation(ds_interp_t *st, VALUE content_str) {
    VALUE str = rb_String(content_str);

    struct ds_interp_eval_ctx ctx = { st, str };

    int state = 0;

    VALUE result = rb_protect(ds_eval_interpolation_inner, (VALUE)&ctx, &state);

    if (state) {
        VALUE err = rb_errinfo();

        rb_set_errinfo(Qnil);

        if (rb_obj_is_kind_of(err, cLexerError) || rb_obj_is_kind_of(err, cParserError)) {

            VALUE inspected = rb_funcall(str, id_inspect, 0);
            VALUE err_msg = rb_funcall(err, id_message, 0);
            VALUE err_str = rb_String(err_msg);
            VALUE message = rb_str_new_cstr("Error evaluating interpolation ");

            rb_str_cat(message, RSTRING_PTR(inspected), RSTRING_LEN(inspected));
            rb_str_cat2(message, ": ");
            rb_str_cat(message, RSTRING_PTR(err_str), RSTRING_LEN(err_str));
            rb_raise(cInterpreterError, "%s", StringValueCStr(message));

        } else {
            rb_exc_raise(err);

        }
    }

    return result;
}

static VALUE ds_visit_interpolated_string(ds_interp_t *st, VALUE node) {
    VALUE parts = rb_funcall(node, SYM2ID(sym_parts), 0);

    long len = RARRAY_LEN(parts);

    VALUE out = rb_str_new("", 0);

    for (long i = 0; i < len; ++i) {
        VALUE pair = rb_ary_entry(parts, i);
        VALUE type = rb_ary_entry(pair, 0);
        VALUE content = rb_ary_entry(pair, 1);

        if (SYM2ID(type) == id_part_string) {
            rb_str_cat(out, RSTRING_PTR(content), RSTRING_LEN(content));
        } else {
            VALUE val = ds_eval_interpolation(st, content);
            VALUE str = rb_String(val);
            rb_str_cat(out, RSTRING_PTR(str), RSTRING_LEN(str));
        }
    }

    return out;
}

static VALUE ds_visit_debug_print(ds_interp_t *st, VALUE node) {
    VALUE expr_node = rb_funcall(node, SYM2ID(sym_expression), 0);
    VALUE value = ds_visit(st, expr_node);
    VALUE formatted = ds_format_value(st, value);
    VALUE formatted_str = rb_String(formatted);
    VALUE source = rb_funcall(node, id_to_source, 0);
    VALUE text = rb_str_dup(rb_String(source));

    rb_str_cat2(text, " # => ");
    rb_str_cat(text, RSTRING_PTR(formatted_str), RSTRING_LEN(formatted_str));
    ds_append_output(st, text);

    return Qnil;
}

static void ds_visit_block(ds_interp_t *st, VALUE stmts_ary) {
    long len = RARRAY_LEN(stmts_ary);

    for (long i = 0; i < len; ++i) {
        VALUE stmt = rb_ary_entry(stmts_ary, i);
        ds_visit(st, stmt);
    }
}

static VALUE ds_visit_if(ds_interp_t *st, VALUE node) {
    VALUE condition = ds_visit(st, rb_funcall(node, SYM2ID(sym_condition), 0));

    if (ds_is_truthy(condition)) {
        VALUE then_block = rb_funcall(node, SYM2ID(sym_then_block), 0);

        ds_visit_block(st, then_block);

        return Qnil;
    }

    VALUE elsif_blocks = rb_funcall(node, SYM2ID(sym_elsif_blocks), 0);

    long len = RARRAY_LEN(elsif_blocks);

    for (long i = 0; i < len; ++i) {
        VALUE clause = rb_ary_entry(elsif_blocks, i);
        VALUE clause_cond = ds_visit(st, rb_funcall(clause, SYM2ID(sym_condition), 0));

        if (ds_is_truthy(clause_cond)) {
            VALUE clause_block = rb_funcall(clause, SYM2ID(sym_block), 0);

            ds_visit_block(st, clause_block);

            return Qnil;
        }
    }

    VALUE else_block = rb_funcall(node, SYM2ID(sym_else_block), 0);

    if (else_block != Qnil) {
        ds_visit_block(st, else_block);
    }

    return Qnil;
}

static VALUE ds_visit_while(ds_interp_t *st, VALUE node) {
    while (ds_is_truthy(ds_visit(st, rb_funcall(node, SYM2ID(sym_condition), 0)))) {
        VALUE block = rb_funcall(node, SYM2ID(sym_block), 0);

        ds_visit_block(st, block);
    }

    return Qnil;
}

static VALUE ds_visit_function_def(ds_interp_t *st, VALUE node) {
    VALUE name = rb_funcall(node, SYM2ID(sym_name), 0);
    VALUE sym = RB_TYPE_P(name, T_SYMBOL) ? name : rb_str_intern(name);
    VALUE params = rb_funcall(node, SYM2ID(sym_parameters), 0);
    VALUE body = rb_funcall(node, SYM2ID(sym_body), 0);
    VALUE closure = rb_funcall(ds_current_scope(st), id_dup, 0);
    VALUE fn = rb_hash_new();

    rb_hash_aset(fn, ID2SYM(id_fn_kind), rb_str_new_cstr("fn"));
    rb_hash_aset(fn, ID2SYM(id_fn_name), sym);
    rb_hash_aset(fn, ID2SYM(id_fn_params), params);
    rb_hash_aset(fn, ID2SYM(id_fn_body), body);
    rb_hash_aset(fn, ID2SYM(id_fn_closure), closure);

    ds_set(st, sym, fn);

    return Qnil;
}

static VALUE ds_visit_return(ds_interp_t *st, VALUE node) {
    VALUE val_node = rb_funcall(node, SYM2ID(sym_value), 0);
    VALUE val = Qnil;

    if (val_node != Qnil) {
        val = ds_visit(st, val_node);
    }

    VALUE argv[1] = { val };
    VALUE ex = rb_class_new_instance(1, argv, cReturnValue);

    rb_exc_raise(ex);

    return Qnil;
}

struct ds_body_ctx {
    ds_interp_t *st;
    VALUE body;
};

static VALUE ds_execute_body(VALUE arg) {
    struct ds_body_ctx *ctx = (struct ds_body_ctx *)arg;

    VALUE result = Qnil;

    long len = RARRAY_LEN(ctx->body);

    for (long i = 0; i < len; ++i) {
        VALUE stmt = rb_ary_entry(ctx->body, i);
        result = ds_visit(ctx->st, stmt);
    }

    return result;
}

static VALUE ds_call_user_function(ds_interp_t *st, VALUE fn, VALUE arg_nodes) {
    VALUE params = rb_hash_aref(fn, ID2SYM(id_fn_params));
    VALUE body = rb_hash_aref(fn, ID2SYM(id_fn_body));
    VALUE closure = rb_hash_aref(fn, ID2SYM(id_fn_closure));

    long expected = RARRAY_LEN(params);

    long given = RARRAY_LEN(arg_nodes);

    if (expected != given) {
        rb_raise(cInterpreterError, "Function expects %ld args, got %ld", expected, given);
    }

    VALUE args = rb_ary_new2(given);

    for (long i = 0; i < given; ++i) {
        VALUE arg_node = rb_ary_entry(arg_nodes, i);
        VALUE value = ds_visit(st, arg_node);

        rb_ary_store(args, i, value);
    }

    VALUE new_scope = rb_funcall(closure, id_dup, 0);

    for (long i = 0; i < expected; ++i) {
        VALUE pname = rb_ary_entry(params, i);
        VALUE psym = RB_TYPE_P(pname, T_SYMBOL) ? pname : rb_str_intern(pname);

        rb_hash_aset(new_scope, psym, rb_ary_entry(args, i));
    }

    rb_ary_push(st->scopes, new_scope);

    int state = 0;
    struct ds_body_ctx ctx = { st, body };

    VALUE result = rb_protect(ds_execute_body, (VALUE)&ctx, &state);

    rb_ary_pop(st->scopes);

    if (state) {
        VALUE err = rb_errinfo();

        rb_set_errinfo(Qnil);

        if (rb_obj_is_kind_of(err, cReturnValue)) {
            result = rb_funcall(err, id_value_method, 0);
        } else {
            rb_exc_raise(err);
        }
    }

    return result;
}

static VALUE ds_visit_method_call(ds_interp_t *st, VALUE node) {
    VALUE name_val = rb_funcall(node, SYM2ID(sym_name), 0);

    ID name_id = RB_TYPE_P(name_val, T_SYMBOL) ? SYM2ID(name_val) : rb_intern(StringValueCStr(name_val));

    VALUE receiver_node = rb_funcall(node, SYM2ID(sym_receiver), 0);
    VALUE args = rb_funcall(node, SYM2ID(sym_arguments), 0);

    if (receiver_node != Qnil) {
        VALUE receiver = ds_visit(st, receiver_node);

        long argc = RARRAY_LEN(args);

        VALUE *argv = NULL;

        if (argc > 0) {
            argv = ALLOCA_N(VALUE, argc);

            for (long i = 0; i < argc; ++i) {
                argv[i] = ds_visit(st, rb_ary_entry(args, i));
            }
        }

        if (RB_TYPE_P(receiver, T_ARRAY)) {
            if (name_id == id_length || name_id == id_size) return rb_funcall(receiver, name_id, 0);

            if (name_id == id_push) {
                for (long i = 0; i < argc; ++i) {
                    rb_ary_push(receiver, argv[i]);
                }
                return receiver;
            }

            if (name_id == id_pop) return rb_ary_pop(receiver);
            if (name_id == id_first) return rb_funcall(receiver, id_first, 0);
            if (name_id == id_last) return rb_funcall(receiver, id_last, 0);
            if (name_id == id_empty || name_id == id_empty_q) return rb_funcall(receiver, id_empty_q, 0);

            rb_raise(cInterpreterError, "Unknown Array method");
        }

        if (RB_TYPE_P(receiver, T_STRING)) {
            if (name_id == id_length || name_id == id_size) return rb_funcall(receiver, name_id, 0);
            if (name_id == id_upcase || name_id == id_downcase || name_id == id_reverse) return rb_funcall(receiver, name_id, 0);
            if (name_id == id_empty || name_id == id_empty_q) return rb_funcall(receiver, id_empty_q, 0);

            rb_raise(cInterpreterError, "Unknown String method");
        }

        rb_raise(cInterpreterError, "Receiver-method dispatch not supported on %s", ds_classname(receiver));
    }

    if (name_id == id_echo || name_id == id_legacy_puts) {
        long argc = RARRAY_LEN(args);

        VALUE parts = rb_ary_new2(argc);

        for (long i = 0; i < argc; ++i) {
            VALUE value = ds_visit(st, rb_ary_entry(args, i));

            rb_ary_store(parts, i, value);
        }

        VALUE joined = rb_ary_join(parts, rb_str_new_cstr(" "));

        ds_append_output(st, joined);

        return Qnil;
    }

    if (name_id == id_typeof) {
        if (RARRAY_LEN(args) != 1) {
            rb_raise(cInterpreterError, "typeof expects 1 argument");
        }

        VALUE value = ds_visit(st, rb_ary_entry(args, 0));

        if (RB_TYPE_P(value, T_STRING))   return rb_str_new_cstr("String");
        if (RB_INTEGER_TYPE_P(value))     return rb_str_new_cstr("Integer");
        if (RB_TYPE_P(value, T_FLOAT))    return rb_str_new_cstr("Float");
        if (value == Qtrue || value == Qfalse) return rb_str_new_cstr("Boolean");
        if (value == Qnil)                return rb_str_new_cstr("Nil");
        if (RB_TYPE_P(value, T_ARRAY))    return rb_str_new_cstr("Array");

        VALUE klass = rb_obj_class(value);

        return rb_funcall(klass, rb_intern("name"), 0);
    }

    VALUE sym = RB_TYPE_P(name_val, T_SYMBOL) ? name_val : rb_str_intern(name_val);
    VALUE fn = Qnil;

    int found = 0;

    for (long i = RARRAY_LEN(st->scopes) - 1; i >= 0; --i) {
        VALUE scope = rb_ary_entry(st->scopes, i);
        VALUE candidate = rb_hash_lookup2(scope, sym, Qundef);

        if (candidate != Qundef) {
            fn = candidate;
            found = 1;
            break;
        }
    }

    if (!found) {
        rb_raise(cInterpreterError, "Unknown method or variable");
    }

    VALUE kind = rb_hash_aref(fn, ID2SYM(id_fn_kind));

    if (!RB_TYPE_P(kind, T_STRING) || strcmp(StringValueCStr(kind), "fn") != 0) {
        rb_raise(cInterpreterError, "Variable is not a function");
    }

    return ds_call_user_function(st, fn, args);
}

static VALUE ds_visit_node(ds_interp_t *st, VALUE node) {

    const char *klass = ds_classname(node);

    if (strstr(klass, "AST::Program"))             return ds_visit_program(st, node);
    if (strstr(klass, "AST::Literal"))             return ds_visit_literal(st, node);
    if (strstr(klass, "AST::Variable"))            return ds_visit_variable(st, node);
    if (strstr(klass, "AST::Assignment"))          return ds_visit_assignment(st, node);
    if (strstr(klass, "AST::BinaryOp"))            return ds_visit_binary(st, node);
    if (strstr(klass, "AST::MethodCall"))          return ds_visit_method_call(st, node);
    if (strstr(klass, "AST::DebugPrint"))          return ds_visit_debug_print(st, node);
    if (strstr(klass, "AST::ArrayLiteral"))        return ds_visit_array_literal(st, node);
    if (strstr(klass, "AST::IndexAccess"))         return ds_visit_index_access(st, node);
    if (strstr(klass, "AST::InterpolatedString"))  return ds_visit_interpolated_string(st, node);
    if (strstr(klass, "AST::IfStatement"))         return ds_visit_if(st, node);
    if (strstr(klass, "AST::WhileStatement"))      return ds_visit_while(st, node);
    if (strstr(klass, "AST::FunctionDef"))         return ds_visit_function_def(st, node);
    if (strstr(klass, "AST::ReturnStatement"))     return ds_visit_return(st, node);

    rb_raise(cInterpreterError, "Unknown AST node type: %s", klass);

    return Qnil;
}

static VALUE ds_visit(ds_interp_t *st, VALUE node) {
    return ds_visit_node(st, node);
}

static VALUE ds_interp_interpret(VALUE self, VALUE ast) {
    ds_interp_t *st;

    TypedData_Get_Struct(self, ds_interp_t, &ds_interp_type, st);

    if (st->ruby_interpreter == Qnil) {
        VALUE interpreter_class = rb_const_get(mDragonstone, rb_intern("Interpreter"));
        st->ruby_interpreter = rb_class_new_instance(0, NULL, interpreter_class);
    }

    rb_iv_set(st->ruby_interpreter, "@log_to_stdout", st->log_to_stdout);
    rb_iv_set(st->ruby_interpreter, "@output", rb_str_new("", 0));

    VALUE output = rb_funcall(st->ruby_interpreter, rb_intern("interpret"), 1, ast);

    st->output = output;

    return output;
}

/*

C entry.

*/

int ds_run_source(const char *src) {
    VALUE lexer_class = ds_const_under(mDragonstone, "Lexer");
    VALUE parser_class = ds_const_under(mDragonstone, "Parser");

    VALUE rsrc = rb_str_new_cstr(src);
    VALUE lexer_args[1] = { rsrc };
    VALUE lexer = rb_class_new_instance(1, lexer_args, lexer_class);
    VALUE tokens = rb_funcall(lexer, id_tokenize, 0);

    VALUE parser_args[1] = { tokens };
    VALUE parser = rb_class_new_instance(1, parser_args, parser_class);
    VALUE ast = rb_funcall(parser, id_parse, 0);

    VALUE interp = rb_class_new_instance(0, NULL, cInterpreter);
    VALUE output = ds_interp_interpret(interp, ast);

    rb_funcall(rb_mKernel, rb_intern("print"), 1, output);

    return 0;
}

VALUE ds_const_under(VALUE outer, const char *name) {
    ID id = rb_intern(name);

    return rb_const_get(outer, id);
}

/*



*/
void Init_dragonstone_Core_interpreter(void) {

    mDragonstone = rb_define_module("Dragonstone");
    mCore = rb_define_module_under(mDragonstone, "Core");
    cInterpreter = rb_define_class_under(mCore, "Interpreter", rb_cObject);

    rb_define_alloc_func(cInterpreter, ds_interp_alloc);
    rb_define_method(cInterpreter, "initialize", RUBY_METHOD_FUNC(ds_interp_initialize), -1);
    rb_define_method(cInterpreter, "interpret", RUBY_METHOD_FUNC(ds_interp_interpret), 1);

    sym_statements   = ID2SYM(rb_intern("statements"));
    sym_name         = ID2SYM(rb_intern("name"));
    sym_receiver     = ID2SYM(rb_intern("receiver"));
    sym_arguments    = ID2SYM(rb_intern("arguments"));
    sym_value        = ID2SYM(rb_intern("value"));
    sym_left         = ID2SYM(rb_intern("left"));
    sym_right        = ID2SYM(rb_intern("right"));
    sym_operator     = ID2SYM(rb_intern("operator"));
    sym_condition    = ID2SYM(rb_intern("condition"));
    sym_then_block   = ID2SYM(rb_intern("then_block"));
    sym_elsif_blocks = ID2SYM(rb_intern("elsif_blocks"));
    sym_else_block   = ID2SYM(rb_intern("else_block"));
    sym_elements     = ID2SYM(rb_intern("elements"));
    sym_object       = ID2SYM(rb_intern("object"));
    sym_index        = ID2SYM(rb_intern("index"));
    sym_body         = ID2SYM(rb_intern("body"));
    sym_parameters   = ID2SYM(rb_intern("parameters"));
    sym_block        = ID2SYM(rb_intern("block"));
    sym_parts        = ID2SYM(rb_intern("parts"));
    sym_expression   = ID2SYM(rb_intern("expression"));

    id_echo         = rb_intern("echo");
    id_legacy_puts  = rb_intern("puts");
    id_kernel_puts  = rb_intern("puts");
    id_typeof = rb_intern("typeof");
    id_length = rb_intern("length");
    id_size   = rb_intern("size");
    id_upcase = rb_intern("upcase");
    id_downcase = rb_intern("downcase");
    id_reverse = rb_intern("reverse");
    id_empty = rb_intern("empty");
    id_empty_q = rb_intern("empty?");
    id_to_f = rb_intern("to_f");
    id_dup  = rb_intern("dup");
    id_to_s = rb_intern("to_s");
    id_inspect = rb_intern("inspect");
    id_to_source = rb_intern("to_source");
    id_message = rb_intern("message");

    id_method_plus          = rb_intern("+");
    id_method_minus         = rb_intern("-");
    id_method_multiply      = rb_intern("*");
    id_method_divide        = rb_intern("/");
    id_method_equals        = rb_intern("==");
    id_method_not_equals    = rb_intern("!=");
    id_method_less          = rb_intern("<");
    id_method_less_equal    = rb_intern("<=");
    id_method_greater       = rb_intern(">");
    id_method_greater_equal = rb_intern(">=");

    id_push  = rb_intern("push");
    id_pop   = rb_intern("pop");
    id_first = rb_intern("first");
    id_last  = rb_intern("last");

    id_tokenize = rb_intern("tokenize");
    id_parse = rb_intern("parse");
    id_parse_expression_entry = rb_intern("parse_expression_entry");
    id_value_method = rb_intern("value");

    id_op_plus          = rb_intern("PLUS");
    id_op_minus         = rb_intern("MINUS");
    id_op_multiply      = rb_intern("MULTIPLY");
    id_op_divide        = rb_intern("DIVIDE");
    id_op_equals        = rb_intern("EQUALS");
    id_op_not_equals    = rb_intern("NOT_EQUALS");
    id_op_less          = rb_intern("LESS");
    id_op_less_equal    = rb_intern("LESS_EQUAL");
    id_op_greater       = rb_intern("GREATER");
    id_op_greater_equal = rb_intern("GREATER_EQUAL");

    id_part_string = rb_intern("string");

    id_fn_kind    = rb_intern("kind");
    id_fn_name    = rb_intern("name");
    id_fn_params  = rb_intern("params");
    id_fn_body    = rb_intern("body");
    id_fn_closure = rb_intern("closure");

    cReturnValue = rb_path2class("Dragonstone::ReturnValue");
    cInterpreterError = rb_path2class("Dragonstone::InterpreterError");
    cLexerError = rb_path2class("Dragonstone::LexerError");
    cParserError = rb_path2class("Dragonstone::ParserError");
    cLexer = ds_const_under(mDragonstone, "Lexer");
    cParser = ds_const_under(mDragonstone, "Parser");
}
