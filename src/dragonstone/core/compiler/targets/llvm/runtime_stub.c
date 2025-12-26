#define _CRT_SECURE_NO_WARNINGS
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <ctype.h>
#include <setjmp.h>
#include <math.h>
#include "../../../../shared/runtime/abi/abi.h"
#if defined(_WIN32)
#include <direct.h>
#else
#include <sys/stat.h>
#include <unistd.h>
#endif

#if defined(_MSC_VER)
#define NORETURN __declspec(noreturn)
#else
#define NORETURN __attribute__((noreturn))
#endif

#define DS_BOX_MAGIC 0x4453564cU

typedef enum {
    DS_VALUE_INT32,
    DS_VALUE_INT64,
    DS_VALUE_BOOL,
    DS_VALUE_FLOAT,
    DS_VALUE_STRUCT,
    DS_VALUE_ARRAY,
    DS_VALUE_CLASS,
    DS_VALUE_INSTANCE,
    DS_VALUE_MAP,
    DS_VALUE_BLOCK,
    DS_VALUE_RANGE,
    DS_VALUE_TUPLE,
    DS_VALUE_NAMED_TUPLE,
    DS_VALUE_ENUM,
    DS_VALUE_BAG_CONSTRUCTOR,
    DS_VALUE_BAG
} DSValueKind;

typedef struct {
    uint32_t magic;
    DSValueKind kind;
    union {
        int32_t i32;
        int64_t i64;
        bool boolean;
        double f64;
        void* ptr;
    } as;
} DSValue;

typedef struct {
    int64_t length;
    void **items;
} DSArray;

typedef struct DSMapEntry {
    void *key;
    void *value;
    struct DSMapEntry *next;
} DSMapEntry;

typedef struct {
    DSMapEntry *head;
    int64_t count;
} DSMap;

typedef void* (*BlockFunc)(void*, int64_t, void**);

typedef struct {
    BlockFunc func;
    void *env;
} DSBlock;

static void *ds_alloc(size_t size);

static void ds_map_append_entry(DSMap *map, void *key, void *value) {
    DSMapEntry *entry = (DSMapEntry *)ds_alloc(sizeof(DSMapEntry));
    entry->key = key;
    entry->value = value;
    entry->next = NULL;

    if (!map->head) {
        map->head = entry;
    } else {
        DSMapEntry *tail = map->head;
        while (tail->next) {
            tail = tail->next;
        }
        tail->next = entry;
    }

    map->count++;
}

typedef struct DSMethod {
    char *name;
    void *func_ptr;
    bool expects_block;
    struct DSMethod *next;
} DSMethod;

typedef struct DSSingletonMethod {
    void *receiver;
    char *name;
    void *func_ptr;
    struct DSSingletonMethod *next;
} DSSingletonMethod;

typedef struct DSConstant {
    char *name;
    void *value;
    struct DSConstant *next;
} DSConstant;

typedef struct DSClass {
    char *name;
    DSMethod *methods;
    DSConstant *constants;
    struct DSClass *superclass;
    struct DSClass *next;
    bool is_module;
    void *cached_box;
} DSClass;

typedef struct {
    DSClass *klass;
    DSMap *ivars;
} DSInstance;

typedef struct {
    int64_t from;
    int64_t to;
    bool exclusive;
    bool is_char;
} DSRange;

typedef struct {
    int64_t length;
    void **items;
} DSTuple;

typedef struct {
    int64_t length;
    char **keys;
    void **values;
} DSNamedTuple;

typedef struct {
    DSClass *klass;
    int64_t value;
    char *name;
} DSEnum;

typedef struct {
    char *element_type;
} DSBagConstructor;

typedef struct {
    DSArray *items;
} DSBag;

static DSClass *global_classes = NULL;

typedef struct DSExceptionFrame {
    jmp_buf env;
    struct DSExceptionFrame *prev;
} DSExceptionFrame;

static DSExceptionFrame *top_exception_frame = NULL;
static void *current_exception_object = NULL;
static DSSingletonMethod *singleton_methods = NULL;
static DSValue *root_self_box = NULL;
static DSValue *ds_program_argv_box = NULL;
static void *ds_builtin_stdout = NULL;
static void *ds_builtin_stderr = NULL;
static void *ds_builtin_stdin = NULL;
static void *ds_builtin_argf = NULL;
static void *ds_builtin_io_stream_class = NULL;
static void *ds_builtin_stdin_class = NULL;
static void *ds_builtin_argf_class = NULL;
static bool ds_io_builtins_initialized = false;

void dragonstone_runtime_push_exception_frame(void *frame_ptr) {
    DSExceptionFrame *frame = (DSExceptionFrame *)frame_ptr;
    frame->prev = top_exception_frame;
    top_exception_frame = frame;
}

void dragonstone_runtime_pop_exception_frame(void) {
    if (top_exception_frame) {
        top_exception_frame = top_exception_frame->prev;
    }
}

void *dragonstone_runtime_get_exception(void) {
    return current_exception_object;
}

static const char DS_STR_NIL_VAL[] = "nil";
static const char DS_STR_TRUE_VAL[] = "true";
static const char DS_STR_FALSE_VAL[] = "false";

static DSConstant *global_constants = NULL;
static void *ds_alloc(size_t size) {
    void *buffer = calloc(1, size);
    if (!buffer) {
        fprintf(stderr, "[fatal] Out of memory\n");
        abort();
    }
    return buffer;
}

static char *ds_strdup(const char *input) {
    if (!input) return NULL;
    size_t len = strlen(input);
    char *copy = (char *)ds_alloc(len + 1);
    memcpy(copy, input, len + 1);
    return copy;
}

static DSValue *ds_new_box(DSValueKind kind) {
    DSValue *value = (DSValue *)ds_alloc(sizeof(DSValue));
    value->magic = DS_BOX_MAGIC;
    value->kind = kind;
    return value;
}

static bool ds_is_boxed(void *value) {
    if (!value) return false;
    DSValue *box = (DSValue *)value;
    return box->magic == DS_BOX_MAGIC;
}

/* Forward decls used by ffi shims. */
void *dragonstone_runtime_to_string(void *value);
void *dragonstone_runtime_box_bool(int32_t value);
void *dragonstone_runtime_box_i64(int64_t value);
void *dragonstone_runtime_array_literal(int64_t length, void **elements);
_Bool dragonstone_runtime_is_truthy(void *value);

static int ds_mkdir_one(const char *path) {
#if defined(_WIN32)
    return _mkdir(path);
#else
    return mkdir(path, 0777);
#endif
}

static int ds_rmdir_one(const char *path) {
#if defined(_WIN32)
    return _rmdir(path);
#else
    return rmdir(path);
#endif
}

static bool ds_mkdirs(const char *path) {
    if (!path || !*path) return false;

    size_t len = strlen(path);
    char *buf = (char *)ds_alloc(len + 1);
    memcpy(buf, path, len + 1);

    /* Normalize separators in-place. */
    for (size_t i = 0; i < len; i++) {
        if (buf[i] == '\\') buf[i] = '/';
    }

    size_t start = 0;
    if (len >= 2 && isalpha((unsigned char)buf[0]) && buf[1] == ':') {
        start = 2;
    }

    for (size_t i = start; i < len; i++) {
        if (buf[i] == '/') {
            if (i == 0) continue;
            buf[i] = '\0';
            if (strlen(buf) > 0) {
                ds_mkdir_one(buf);
            }
            buf[i] = '/';
        }
    }

    ds_mkdir_one(buf);
    return true;
}

static const char *ds_arg_string(void *v) {
    if (!v) return NULL;
    if (!ds_is_boxed(v)) return (const char *)v;
    void *str = dragonstone_runtime_to_string(v);
    return (const char *)str;
}

static bool ds_arg_bool(void *v) {
    if (!v) return false;
    if (!ds_is_boxed(v)) return false;
    DSValue *box = (DSValue *)v;
    if (box->kind != DS_VALUE_BOOL) return false;
    return box->as.boolean;
}

static DSArray *ds_unwrap_array(void *value) {
    if (!value || !ds_is_boxed(value)) return NULL;
    DSValue *box = (DSValue *)value;
    if (box->kind != DS_VALUE_ARRAY) return NULL;
    return (DSArray *)box->as.ptr;
}

static char *ds_slice_string(const char *src, int64_t start, int64_t length) {
    size_t slen = strlen(src);
    if (start < 0 || (size_t)start >= slen || length <= 0) {
        return ds_strdup("");
    }
    if ((size_t)(start + length) > slen) {
        length = (int64_t)(slen - (size_t)start);
    }
    char *buf = (char *)ds_alloc((size_t)length + 1);
    memcpy(buf, src + start, (size_t)length);
    buf[length] = '\0';
    return buf;
}

static char *ds_strip_string(const char *src) {
    size_t len = strlen(src);
    size_t start = 0;
    while (start < len && isspace((unsigned char)src[start])) start++;
    if (start == len) return ds_strdup("");
    size_t end = len;
    while (end > start && isspace((unsigned char)src[end - 1])) end--;
    size_t out_len = end - start;
    char *buf = (char *)ds_alloc(out_len + 1);
    memcpy(buf, src + start, out_len);
    buf[out_len] = '\0';
    return buf;
}

static void ds_constant_set(DSConstant **head, const char *name, void *value) {
    DSConstant *curr = *head;
    while (curr) {
        if (strcmp(curr->name, name) == 0) {
            curr->value = value;
            return;
        }
        curr = curr->next;
    }
    DSConstant *node = (DSConstant *)ds_alloc(sizeof(DSConstant));
    node->name = ds_strdup(name);
    node->value = value;
    node->next = *head;
    *head = node;
}

static void *ds_constant_get(DSConstant *head, const char *name) {
    DSConstant *curr = head;
    while (curr) {
        if (strcmp(curr->name, name) == 0) {
            return curr->value;
        }
        curr = curr->next;
    }
    return NULL;
}

static char *ds_join_path(const char *lhs, const char *rhs) {
    size_t len_l = strlen(lhs);
    size_t len_r = strlen(rhs);
    char *buffer = (char *)ds_alloc(len_l + len_r + 3);
    memcpy(buffer, lhs, len_l);
    buffer[len_l] = ':';
    buffer[len_l + 1] = ':';
    memcpy(buffer + len_l + 2, rhs, len_r + 1);
    return buffer;
}

_Bool dragonstone_runtime_case_compare(void *lhs, void *rhs);
void *dragonstone_runtime_array_literal(int64_t length, void **elements);
void *dragonstone_runtime_value_display(void *value);
void *dragonstone_runtime_box_i64(int64_t v);
void *dragonstone_runtime_box_bool(int32_t v);
void *dragonstone_runtime_array_push(void *array_val, void *value);
void *dragonstone_runtime_block_invoke(void *block_val, int64_t argc, void **argv);
void *dragonstone_runtime_bag_constructor(void *element_type);
void *dragonstone_runtime_add(void *lhs, void *rhs);
void *dragonstone_runtime_sub(void *lhs, void *rhs);
void *dragonstone_runtime_mul(void *lhs, void *rhs);
void *dragonstone_runtime_div(void *lhs, void *rhs);
void *dragonstone_runtime_mod(void *lhs, void *rhs);
void *dragonstone_runtime_negate(void *value);
void *dragonstone_runtime_to_string(void *value);
void *dragonstone_runtime_tuple_literal(int64_t l, void **e);
void *dragonstone_runtime_named_tuple_literal(int64_t l, void **k, void **v);
void dragonstone_runtime_set_argv(int64_t argc, char **argv);
void *dragonstone_runtime_argv(void);
void *dragonstone_runtime_argc(void);
void *dragonstone_runtime_stdout(void);
void *dragonstone_runtime_stderr(void);
void *dragonstone_runtime_stdin(void);
void *dragonstone_runtime_argf(void);

void *dragonstone_runtime_gt(void *lhs, void *rhs);
void *dragonstone_runtime_lt(void *lhs, void *rhs);
void *dragonstone_runtime_gte(void *lhs, void *rhs);
void *dragonstone_runtime_lte(void *lhs, void *rhs);
void *dragonstone_runtime_eq(void *lhs, void *rhs);
void *dragonstone_runtime_ne(void *lhs, void *rhs);
void *dragonstone_runtime_shl(void *lhs, void *rhs);
void *dragonstone_runtime_shr(void *lhs, void *rhs);
void *dragonstone_runtime_pow(void *lhs, void *rhs);
void *dragonstone_runtime_floor_div(void *lhs, void *rhs);
void *dragonstone_runtime_cmp(void *lhs, void *rhs);

void dragonstone_runtime_raise(void *message_ptr) {
    if (top_exception_frame) {
        current_exception_object = message_ptr;
        longjmp(top_exception_frame->env, 1);
    } else {
        const char *msg = (const char *)message_ptr;
        fprintf(stderr, "Runtime Error: %s\n", msg ? msg : "Unknown error");
        abort();
    }
}

static DSValue *ds_create_array_box(int64_t length, void **elements) {
    DSArray *array = (DSArray *)ds_alloc(sizeof(DSArray));
    array->length = length;
    if (length > 0) {
        array->items = (void **)ds_alloc(sizeof(void *) * (size_t)length);
        if (elements) {
            for (int64_t i = 0; i < length; ++i) {
                array->items[i] = elements[i];
            }
        }
    } else {
        array->items = NULL;
    }
    
    DSValue *box = ds_new_box(DS_VALUE_ARRAY);
    box->as.ptr = array;
    return box;
}

static DSValue *ds_create_map_box(int64_t length, void **keys, void **values) {
    DSMap *map = (DSMap *)ds_alloc(sizeof(DSMap));
    map->head = NULL;
    map->count = 0;

    for (int64_t i = 0; i < length; ++i) {
        ds_map_append_entry(map, keys[i], values[i]);
    }

    DSValue *box = ds_new_box(DS_VALUE_MAP);
    box->as.ptr = map;
    return box;
}

void *dragonstone_runtime_box_i32(int32_t v) { DSValue *b = ds_new_box(DS_VALUE_INT32); b->as.i32 = v; return b; }
void *dragonstone_runtime_box_i64(int64_t v) { DSValue *b = ds_new_box(DS_VALUE_INT64); b->as.i64 = v; return b; }
void *dragonstone_runtime_box_bool(int32_t v) { DSValue *b = ds_new_box(DS_VALUE_BOOL); b->as.boolean = v; return b; }
void *dragonstone_runtime_box_float(double v) { DSValue *b = ds_new_box(DS_VALUE_FLOAT); b->as.f64 = v; return b; }
void *dragonstone_runtime_box_string(void *v) { return v; }

void* dragonstone_runtime_box_struct(void* data, int64_t size) {
    DSValue* box = ds_new_box(DS_VALUE_STRUCT);
    void* heap_copy = ds_alloc((size_t)size);
    memcpy(heap_copy, data, (size_t)size);
    box->as.ptr = heap_copy;
    return box;
}

void* dragonstone_runtime_unbox_struct(void* value) {
    if (!value || !ds_is_boxed(value)) return NULL;
    DSValue* box = (DSValue*)value;
    if (box->kind != DS_VALUE_STRUCT) return NULL;
    return box->as.ptr;
}

int32_t dragonstone_runtime_unbox_i32(void *v) {
    if (!ds_is_boxed(v)) return 0;
    DSValue *box = (DSValue *)v;
    if (box->kind == DS_VALUE_INT32) return box->as.i32;
    if (box->kind == DS_VALUE_INT64) return (int32_t)box->as.i64;
    if (box->kind == DS_VALUE_FLOAT) return (int32_t)box->as.f64;
    return 0;
}

int64_t dragonstone_runtime_unbox_i64(void *v) {
    if (!ds_is_boxed(v)) return 0;
    DSValue *box = (DSValue *)v;
    if (box->kind == DS_VALUE_INT64) return box->as.i64;
    if (box->kind == DS_VALUE_INT32) return (int64_t)box->as.i32;
    if (box->kind == DS_VALUE_FLOAT) return (int64_t)box->as.f64;
    return 0;
}

int32_t dragonstone_runtime_unbox_bool(void *v) { if(ds_is_boxed(v) && ((DSValue*)v)->kind == DS_VALUE_BOOL) return ((DSValue*)v)->as.boolean; return 0; }

double dragonstone_runtime_unbox_float(void *v) {
    if (!ds_is_boxed(v)) return 0.0;
    DSValue *box = (DSValue *)v;
    if (box->kind == DS_VALUE_FLOAT) return box->as.f64;
    if (box->kind == DS_VALUE_INT32) return (double)box->as.i32;
    if (box->kind == DS_VALUE_INT64) return (double)box->as.i64;
    return 0.0;
}

static char *ds_format_value(void *value, bool quote_strings) {
    if (!value) return (void *)DS_STR_NIL_VAL;
    
    if (ds_is_boxed(value)) {
        DSValue *box = (DSValue *)value;
        switch (box->kind) {
            case DS_VALUE_INT32: {
                char buf[32]; snprintf(buf, 32, "%d", box->as.i32); return ds_strdup(buf);
            }
            case DS_VALUE_INT64: {
                char buf[64]; snprintf(buf, 64, "%lld", (long long)box->as.i64); return ds_strdup(buf);
            }
            case DS_VALUE_BOOL: return (void*)(box->as.boolean ? DS_STR_TRUE_VAL : DS_STR_FALSE_VAL);
            case DS_VALUE_FLOAT: {
                char buf[64]; snprintf(buf, 64, "%g", box->as.f64); return ds_strdup(buf);
            }
            case DS_VALUE_STRUCT: return ds_strdup("{Struct}");
            case DS_VALUE_CLASS: return ds_strdup(((DSClass*)box->as.ptr)->name);
            case DS_VALUE_INSTANCE: return ds_strdup("{Instance}"); 
            case DS_VALUE_ARRAY: {
                DSArray *arr = (DSArray *)box->as.ptr;
                if (arr->length == 0) return ds_strdup("[]");
                
                char *buffer = (char *)ds_alloc(1024 * 16); 
                strcpy(buffer, "[");
                for (int64_t i = 0; i < arr->length; ++i) {
                    void *str_ptr = dragonstone_runtime_value_display(arr->items[i]);
                    strcat(buffer, (char *)str_ptr);
                    if (i < arr->length - 1) strcat(buffer, ", ");
                }
                strcat(buffer, "]");
                return buffer;
            }
            case DS_VALUE_MAP: {
                DSMap *map = (DSMap *)box->as.ptr;
                if (map->count == 0) return ds_strdup("{}");
                
                char *buffer = (char *)ds_alloc(1024 * 16);
                strcpy(buffer, "{");
                DSMapEntry *curr = map->head;
                while (curr) {
                    void *k_str = dragonstone_runtime_value_display(curr->key);
                    void *v_str = dragonstone_runtime_value_display(curr->value);
                    strcat(buffer, (char *)k_str);
                    strcat(buffer, " -> ");
                    strcat(buffer, (char *)v_str);
                    if (curr->next) strcat(buffer, ", ");
                    curr = curr->next;
                }
                strcat(buffer, "}");
                return buffer;
            }
            case DS_VALUE_BLOCK: return ds_strdup("{Block}");
            case DS_VALUE_RANGE: {
                DSRange *rng = (DSRange *)box->as.ptr;
                char buf[128];
                snprintf(buf, 128, "%lld%s%lld", (long long)rng->from, rng->exclusive ? "..." : "..", (long long)rng->to);
                return ds_strdup(buf);
            }
            case DS_VALUE_TUPLE: {
                DSTuple *tup = (DSTuple *)box->as.ptr;
                char *buffer = (char *)ds_alloc(1024 * 16);
                strcpy(buffer, "{");
                for (int64_t i = 0; i < tup->length; ++i) {
                    void *str_ptr = dragonstone_runtime_value_display(tup->items[i]);
                    strcat(buffer, (char *)str_ptr);
                    if (i < tup->length - 1) strcat(buffer, ", ");
                }
                strcat(buffer, "}");
                return buffer;
            }
            case DS_VALUE_NAMED_TUPLE: {
                DSNamedTuple *nt = (DSNamedTuple *)box->as.ptr;
                char *buffer = (char *)ds_alloc(1024 * 16);
                strcpy(buffer, "{");
                for (int64_t i = 0; i < nt->length; ++i) {
                    strcat(buffer, nt->keys[i]);
                    strcat(buffer, ": ");
                    void *str_ptr = dragonstone_runtime_value_display(nt->values[i]);
                    strcat(buffer, (char *)str_ptr);
                    if (i < nt->length - 1) strcat(buffer, ", ");
                }
                strcat(buffer, "}");
                return buffer;
            }
            case DS_VALUE_ENUM: {
                DSEnum *e = (DSEnum *)box->as.ptr;
                return ds_strdup(e->name);
            }
            case DS_VALUE_BAG_CONSTRUCTOR: {
                DSBagConstructor *ctor = (DSBagConstructor *)box->as.ptr;
                const char *etype = ctor && ctor->element_type ? ctor->element_type : "dynamic";
                size_t len = strlen(etype) + 6;
                char *buf = (char *)ds_alloc(len);
                snprintf(buf, len, "bag(%s)", etype);
                return buf;
            }
            case DS_VALUE_BAG: {
                return ds_strdup("{Bag}");
            }
        }
    }

    char *str = (char *)value;

    if (quote_strings) {
        size_t len = strlen(str);
        char *quoted = (char *)ds_alloc(len + 3);
        quoted[0] = '"';
        strcpy(quoted + 1, str);
        quoted[len + 1] = '"';
        quoted[len + 2] = '\0';
        return quoted;
    }

    return ds_strdup(str);
}

static char *ds_value_to_string(void *value) {
    if (!value) return ds_strdup("");
    
    if (!ds_is_boxed(value)) {
        return ds_strdup((char *)value);
    }
    
    DSValue *box = (DSValue *)value;
    switch (box->kind) {
        case DS_VALUE_INT32: {
            char buf[32]; 
            snprintf(buf, 32, "%d", box->as.i32); 
            return ds_strdup(buf);
        }
        case DS_VALUE_INT64: {
            char buf[64]; 
            snprintf(buf, 64, "%lld", (long long)box->as.i64); 
            return ds_strdup(buf);
        }
        case DS_VALUE_BOOL: 
            return ds_strdup(box->as.boolean ? "true" : "false");
        case DS_VALUE_FLOAT: {
            char buf[64]; 
            snprintf(buf, 64, "%g", box->as.f64); 
            return ds_strdup(buf);
        }
        default:
            return ds_format_value(value, false);
    }
}

void *dragonstone_runtime_array_push(void *array_val, void *value) {
    DSArray *array = ds_unwrap_array(array_val);
    if (!array) {
        fprintf(stderr, "[runtime] array_push called on non-array\n");
        return array_val;
    }
    
    int64_t new_len = array->length + 1;
    void **new_items = (void **)realloc(array->items, sizeof(void *) * new_len);
    if (!new_items) abort();
    
    array->items = new_items;
    array->items[array->length] = value;
    array->length = new_len;
    
    return array_val;
}

void *dragonstone_runtime_block_literal(BlockFunc f, void *e) {
    DSBlock *blk = (DSBlock *)ds_alloc(sizeof(DSBlock));
    blk->func = f;
    blk->env = e;
    DSValue *box = ds_new_box(DS_VALUE_BLOCK);
    box->as.ptr = blk;
    return box;
}

void *dragonstone_runtime_block_invoke(void *block_val, int64_t argc, void **argv) {
    if (!ds_is_boxed(block_val)) {
        return NULL;
    }
    DSValue *box = (DSValue *)block_val;
    if (box->kind != DS_VALUE_BLOCK) {
        return NULL;
    }
    
    DSBlock *blk = (DSBlock *)box->as.ptr;
    return blk->func(blk->env, argc, argv);
}

typedef void* (*Method0)(void*);
typedef void* (*Method1)(void*, void*);
typedef void* (*Method2)(void*, void*, void*);
typedef void* (*Method3)(void*, void*, void*, void*);
typedef void* (*Method4)(void*, void*, void*, void*, void*);
typedef void* (*Method5)(void*, void*, void*, void*, void*, void*);
typedef void* (*Method6)(void*, void*, void*, void*, void*, void*, void*);
typedef void* (*Method7)(void*, void*, void*, void*, void*, void*, void*, void*);

static void *ds_call_method(void *func_ptr, void *receiver, int64_t argc, void **argv) {
    if (argc == 0) return ((Method0)func_ptr)(receiver);
    if (argc == 1) return ((Method1)func_ptr)(receiver, argv[0]);
    if (argc == 2) return ((Method2)func_ptr)(receiver, argv[0], argv[1]);
    if (argc == 3) return ((Method3)func_ptr)(receiver, argv[0], argv[1], argv[2]);
    if (argc == 4) return ((Method4)func_ptr)(receiver, argv[0], argv[1], argv[2], argv[3]);
    if (argc == 5) return ((Method5)func_ptr)(receiver, argv[0], argv[1], argv[2], argv[3], argv[4]);
    if (argc == 6) return ((Method6)func_ptr)(receiver, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
    if (argc == 7) return ((Method7)func_ptr)(receiver, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
    return NULL;
}

static DSMethod *ds_lookup_method_from(DSClass *cls, const char *name) {
    while (cls) {
        DSMethod *meth = cls->methods;
        while (meth) {
            if (strcmp(meth->name, name) == 0) return meth;
            meth = meth->next;
        }
        cls = cls->superclass;
    }
    return NULL;
}

void dragonstone_runtime_define_singleton_method(void *receiver, void *name_ptr, void *func_ptr) {
    DSSingletonMethod *node = (DSSingletonMethod *)ds_alloc(sizeof(DSSingletonMethod));
    node->receiver = receiver;
    node->name = ds_strdup((char *)name_ptr);
    node->func_ptr = func_ptr;
    node->next = singleton_methods;
    singleton_methods = node;
}

static int64_t ds_get_ordinal(void *val, bool *is_char) {
    if (!val) { *is_char = false; return 0; }
    if (ds_is_boxed(val)) {
        DSValue *box = (DSValue *)val;
        if (box->kind == DS_VALUE_INT32) { *is_char = false; return (int64_t)box->as.i32; }
        if (box->kind == DS_VALUE_INT64) { *is_char = false; return box->as.i64; }
    } else {
        char *str = (char *)val;
        if (str && strlen(str) > 0) {
            *is_char = true;
            return (int64_t)str[0];
        }
    }
    *is_char = false;
    return 0;
}

void *dragonstone_runtime_method_invoke(void *receiver, void *method_name_ptr, int64_t argc, void **argv, void *block_val) {
    const char *method = (const char *)method_name_ptr;

    if (receiver && !ds_is_boxed(receiver)) {
        const char *recv_str = (const char *)receiver;
        if (recv_str && strcmp(recv_str, "ffi") == 0) {
            if (strcmp(method, "call_ruby") == 0 || strcmp(method, "call_crystal") == 0 || strcmp(method, "call_c") == 0) {
                if (argc < 2) return NULL;
                DSArray *args = ds_unwrap_array(argv[1]);
                if (!args || args->length < 1) return NULL;
                const char *fn = ds_arg_string(argv[0]);

                /* Minimal "ffi.call_crystal" shims for stdlib modules. */
                if (strcmp(method, "call_crystal") == 0 && fn) {
                    if (strcmp(fn, "path_create") == 0 && args->length >= 1) {
                        const char *target = ds_arg_string(args->items[0]);
                        if (target) ds_mkdirs(target);
                        return target ? ds_strdup(target) : NULL;
                    }

                    if (strcmp(fn, "path_delete") == 0 && args->length >= 1) {
                        const char *target = ds_arg_string(args->items[0]);
                        if (!target) return NULL;
                        (void)ds_rmdir_one(target);
                        return ds_strdup(target);
                    }

                    if (strcmp(fn, "file_read") == 0 && args->length >= 1) {
                        const char *path = ds_arg_string(args->items[0]);
                        if (!path) return ds_strdup("");
                        FILE *fp = fopen(path, "rb");
                        if (!fp) return ds_strdup("");
                        fseek(fp, 0, SEEK_END);
                        long size = ftell(fp);
                        fseek(fp, 0, SEEK_SET);
                        if (size < 0) { fclose(fp); return ds_strdup(""); }
                        char *buf = (char *)ds_alloc((size_t)size + 1);
                        size_t got = fread(buf, 1, (size_t)size, fp);
                        buf[got] = '\0';
                        fclose(fp);
                        return buf;
                    }

                    if ((strcmp(fn, "file_write") == 0 || strcmp(fn, "file_append") == 0 || strcmp(fn, "file_create") == 0) && args->length >= 2) {
                        const char *path = ds_arg_string(args->items[0]);
                        const char *content = ds_arg_string(args->items[1]);
                        bool create_dirs = (args->length >= 3) ? ds_arg_bool(args->items[2]) : false;
                        if (!path) return NULL;
                        if (create_dirs) {
                            const char *last_slash = strrchr(path, '/');
                            const char *last_bslash = strrchr(path, '\\');
                            const char *sep = last_slash;
                            if (last_bslash && (!sep || last_bslash > sep)) sep = last_bslash;
                            if (sep) {
                                size_t dlen = (size_t)(sep - path);
                                char *dir = (char *)ds_alloc(dlen + 1);
                                memcpy(dir, path, dlen);
                                dir[dlen] = '\0';
                                ds_mkdirs(dir);
                            }
                        }

                        const char *mode = (strcmp(fn, "file_append") == 0) ? "ab" : "wb";
                        FILE *fp = fopen(path, mode);
                        if (!fp) return NULL;
                        size_t len = content ? strlen(content) : 0;
                        size_t wrote = (len > 0) ? fwrite(content, 1, len, fp) : 0;
                        fclose(fp);

                        if (strcmp(fn, "file_create") == 0) {
                            return ds_strdup(path);
                        }
                        return dragonstone_runtime_box_i64((int64_t)wrote);
                    }

                    if (strcmp(fn, "file_delete") == 0 && args->length >= 1) {
                        const char *path = ds_arg_string(args->items[0]);
                        if (!path) return dragonstone_runtime_box_bool(false);

                        int ok = remove(path);
                        if (ok != 0) ok = ds_rmdir_one(path);
                        return dragonstone_runtime_box_bool(ok == 0);
                    }

                    if (strcmp(fn, "file_open") == 0 && args->length >= 2) {
                        const char *path = ds_arg_string(args->items[0]);
                        const char *mode = ds_arg_string(args->items[1]);
                        bool create_dirs = (args->length >= 3) ? ds_arg_bool(args->items[2]) : false;
                        if (!path || !mode) return NULL;

                        if (create_dirs) {
                            const char *last_slash = strrchr(path, '/');
                            const char *last_bslash = strrchr(path, '\\');
                            const char *sep = last_slash;
                            if (last_bslash && (!sep || last_bslash > sep)) sep = last_bslash;
                            if (sep) {
                                size_t dlen = (size_t)(sep - path);
                                char *dir = (char *)ds_alloc(dlen + 1);
                                memcpy(dir, path, dlen);
                                dir[dlen] = '\0';
                                ds_mkdirs(dir);
                            }
                        }

                        FILE *fp = fopen(path, mode);
                        bool success = fp != NULL;
                        int64_t size = 0;
                        if (fp) {
                            fseek(fp, 0, SEEK_END);
                            long fsize = ftell(fp);
                            if (fsize >= 0) size = (int64_t)fsize;
                            fclose(fp);
                        }

                        void **items = (void **)ds_alloc(sizeof(void *) * 4);
                        items[0] = ds_strdup(path);
                        items[1] = ds_strdup(mode);
                        items[2] = dragonstone_runtime_box_bool(success);
                        items[3] = dragonstone_runtime_box_i64(size);
                        return dragonstone_runtime_array_literal(4, items);
                    }
                }

                /* Fallback: preserve interop demo behavior. */
                void *msg = args->items[0];
                if (msg) {
                    if (ds_is_boxed(msg)) {
                        void *disp = dragonstone_runtime_to_string(msg);
                        if (disp) puts((const char *)disp);
                    } else {
                        puts((const char *)msg);
                    }
                }
                return NULL;
            }
        }
    }

    if (receiver == NULL) {
        if (strcmp(method, "nil?") == 0) {
            return dragonstone_runtime_box_bool(true);
        }
        return NULL;
    }

    DSSingletonMethod *snode = singleton_methods;
    while (snode) {
        if (strcmp(snode->name, method) == 0) {
            if (snode->receiver == receiver) {
                return ds_call_method(snode->func_ptr, receiver, argc, argv);
            }
            if (!ds_is_boxed(receiver) && !ds_is_boxed(snode->receiver) && strcmp((char *)snode->receiver, (char *)receiver) == 0) {
                return ds_call_method(snode->func_ptr, receiver, argc, argv);
            }
        }
        snode = snode->next;
    }

    if (ds_is_boxed(receiver) && ((DSValue*)receiver)->kind == DS_VALUE_ENUM) {
        DSEnum *e = (DSEnum *)((DSValue*)receiver)->as.ptr;
        if (strcmp(method, "value") == 0) {
            return dragonstone_runtime_box_i64(e->value);
        }
    }

    if (!ds_is_boxed(receiver)) {
        char *str = (char *)receiver;
        
        if (strcmp(method, "length") == 0 || strcmp(method, "size") == 0) {
            return dragonstone_runtime_box_i64(strlen(str));
        }
        
        if (strcmp(method, "upcase") == 0) {
            char *copy = ds_strdup(str);
            for (int i = 0; copy[i]; i++) copy[i] = toupper(copy[i]);
            return copy;
        }
        
        if (strcmp(method, "downcase") == 0) {
            char *copy = ds_strdup(str);
            for (int i = 0; copy[i]; i++) copy[i] = tolower(copy[i]);
            return copy;
        }

        if (strcmp(method, "strip") == 0) {
            return ds_strip_string(str);
        }

        if (strcmp(method, "slice") == 0) {
            if (argc == 2) {
                int64_t start = dragonstone_runtime_unbox_i64(argv[0]);
                int64_t len = dragonstone_runtime_unbox_i64(argv[1]);
                return ds_slice_string(str, start, len);
            } else if (argc == 1 && ds_is_boxed(argv[0])) {
                DSValue *range_box = (DSValue *)argv[0];
                if (range_box->kind == DS_VALUE_RANGE) {
                    DSRange *rng = (DSRange *)range_box->as.ptr;
                    int64_t len = rng->exclusive ? (rng->to - rng->from) : (rng->to - rng->from + 1);
                    return ds_slice_string(str, rng->from, len);
                }
            }
            return ds_strdup("");
        }

        if (strcmp(method, "inspect") == 0 || strcmp(method, "display") == 0) {
            return dragonstone_runtime_value_display(receiver);
        }

        if (strcmp(method, "message") == 0) {
            return receiver;
        }

        return NULL; 
    }

    DSValue *box = (DSValue *)receiver;

    if (box->kind == DS_VALUE_BLOCK) {
        if (strcmp(method, "call") == 0) {
            return dragonstone_runtime_block_invoke(receiver, argc, argv);
        }
    }

    if (box->kind == DS_VALUE_TUPLE) {
        DSTuple *tup = (DSTuple *)box->as.ptr;
        if (strcmp(method, "length") == 0 || strcmp(method, "size") == 0) {
            return dragonstone_runtime_box_i64(tup->length);
        }
        if (strcmp(method, "first") == 0) {
            if (tup->length == 0) return NULL;
            return tup->items[0];
        }
        if (strcmp(method, "last") == 0) {
            if (tup->length == 0) return NULL;
            return tup->items[tup->length - 1];
        }
        if (strcmp(method, "to_a") == 0) {
            return dragonstone_runtime_array_literal(tup->length, tup->items);
        }
    }

    if (box->kind == DS_VALUE_INT32 || box->kind == DS_VALUE_INT64 ||
        box->kind == DS_VALUE_BOOL || box->kind == DS_VALUE_FLOAT) {
        if (strcmp(method, "display") == 0 || strcmp(method, "inspect") == 0) {
            return dragonstone_runtime_value_display(receiver);
        }
    }

    if (box->kind == DS_VALUE_BAG_CONSTRUCTOR) {
        if (strcmp(method, "new") == 0) {
            DSBag *bag = (DSBag *)ds_alloc(sizeof(DSBag));
            bag->items = (DSArray *)ds_alloc(sizeof(DSArray));
            bag->items->length = 0;
            bag->items->items = NULL;
            DSValue *bag_box = ds_new_box(DS_VALUE_BAG);
            bag_box->as.ptr = bag;
            return bag_box;
        }
    }

    if (box->kind == DS_VALUE_BAG) {
        DSBag *bag = (DSBag *)box->as.ptr;
        DSArray *arr = bag->items;

        if (strcmp(method, "size") == 0 || strcmp(method, "length") == 0) {
            return dragonstone_runtime_box_i64(arr->length);
        }

        if (strcmp(method, "empty") == 0 || strcmp(method, "empty?") == 0) {
            return dragonstone_runtime_box_bool(arr->length == 0);
        }

        if (strcmp(method, "includes?") == 0 || strcmp(method, "member?") == 0 || strcmp(method, "contains?") == 0) {
            if (argc != 1) return dragonstone_runtime_box_bool(false);
            void *target = argv[0];
            for (int64_t i = 0; i < arr->length; i++) {
                if (dragonstone_runtime_case_compare(arr->items[i], target)) {
                    return dragonstone_runtime_box_bool(true);
                }
            }
            return dragonstone_runtime_box_bool(false);
        }

        if (strcmp(method, "add") == 0) {
            if (argc != 1) return receiver;
            void *val = argv[0];
            for (int64_t i = 0; i < arr->length; i++) {
                if (dragonstone_runtime_case_compare(arr->items[i], val)) {
                    return receiver;
                }
            }
            int64_t new_len = arr->length + 1;
            void **new_items = (void **)realloc(arr->items, sizeof(void*) * new_len);
            if (!new_items) abort();
            arr->items = new_items;
            arr->items[arr->length] = val;
            arr->length = new_len;
            return receiver;
        }

        if (strcmp(method, "each") == 0) {
            if (!block_val) return receiver;
            void *args_buf[1];
            for (int64_t i = 0; i < arr->length; i++) {
                args_buf[0] = arr->items[i];
                dragonstone_runtime_block_invoke(block_val, 1, args_buf);
            }
            return receiver;
        }

        if (strcmp(method, "map") == 0) {
            if (!block_val) return receiver;
            void **items = (void **)ds_alloc(sizeof(void*) * arr->length);
            for (int64_t i = 0; i < arr->length; i++) {
                void *args_buf[1];
                args_buf[0] = arr->items[i];
                items[i] = dragonstone_runtime_block_invoke(block_val, 1, args_buf);
            }
            void *res = dragonstone_runtime_array_literal(arr->length, items);
            free(items);
            return res;
        }

        if (strcmp(method, "select") == 0) {
            if (!block_val) return receiver;
            DSBag *out = (DSBag *)ds_alloc(sizeof(DSBag));
            out->items = (DSArray *)ds_alloc(sizeof(DSArray));
            out->items->length = 0;
            out->items->items = NULL;
            void *args_buf[1];
            for (int64_t i = 0; i < arr->length; i++) {
                args_buf[0] = arr->items[i];
                void *res = dragonstone_runtime_block_invoke(block_val, 1, args_buf);
                if (dragonstone_runtime_case_compare(res, dragonstone_runtime_box_bool(true))) {
                    int64_t new_len = out->items->length + 1;
                    void **new_items = (void **)realloc(out->items->items, sizeof(void*) * new_len);
                    if (!new_items) abort();
                    out->items->items = new_items;
                    out->items->items[out->items->length] = arr->items[i];
                    out->items->length = new_len;
                }
            }
            DSValue *box_out = ds_new_box(DS_VALUE_BAG);
            box_out->as.ptr = out;
            return box_out;
        }

        if (strcmp(method, "inject") == 0) {
            if (!block_val) return receiver;
            if (argc > 1) return receiver;
            void *memo = argc == 1 ? argv[0] : NULL;
            void *args_buf[2];
            for (int64_t i = 0; i < arr->length; i++) {
                if (memo == NULL && argc == 0 && i == 0) {
                    memo = arr->items[i];
                    continue;
                }
                args_buf[0] = memo;
                args_buf[1] = arr->items[i];
                memo = dragonstone_runtime_block_invoke(block_val, 2, args_buf);
            }
            return memo;
        }

        if (strcmp(method, "until") == 0) {
            if (!block_val) return receiver;
            void *args_buf[1];
            for (int64_t i = 0; i < arr->length; i++) {
                args_buf[0] = arr->items[i];
                void *res = dragonstone_runtime_block_invoke(block_val, 1, args_buf);
                if (dragonstone_runtime_case_compare(res, dragonstone_runtime_box_bool(true))) {
                    return arr->items[i];
                }
            }
            return NULL;
        }

        if (strcmp(method, "to_a") == 0) {
            void **items = (void **)ds_alloc(sizeof(void*) * arr->length);
            for (int64_t i = 0; i < arr->length; i++) items[i] = arr->items[i];
            void *res = dragonstone_runtime_array_literal(arr->length, items);
            free(items);
            return res;
        }
    }

    if (box->kind == DS_VALUE_CLASS) {
        DSClass *cls = (DSClass *)box->as.ptr;
        if (strcmp(method, "new") == 0 && !cls->is_module) {
            /* Enum-style constructor: match by value if enum members exist. */
            if (argc == 1) {
                int64_t target = dragonstone_runtime_unbox_i64(argv[0]);
                DSConstant *c = cls->constants;
                while (c) {
                    if (ds_is_boxed(c->value) && ((DSValue *)c->value)->kind == DS_VALUE_ENUM) {
                        DSEnum *e = (DSEnum *)((DSValue *)c->value)->as.ptr;
                        if (e && e->klass == cls && e->value == target) {
                            return c->value;
                        }
                    }
                    c = c->next;
                }
            }

            DSInstance *inst = (DSInstance *)ds_alloc(sizeof(DSInstance));
            inst->klass = cls;
            inst->ivars = NULL;
            DSValue *inst_box = ds_new_box(DS_VALUE_INSTANCE);
            inst_box->as.ptr = inst;
            DSMethod *init = ds_lookup_method_from(cls, "initialize");
            if (init) ds_call_method(init->func_ptr, inst_box, argc, argv);
            
            return inst_box;
        }
        DSMethod *meth = ds_lookup_method_from(cls, method);
        if (meth) {
            if (meth->expects_block) {
                int64_t argc2 = argc + 1;
                void *stack_args[8];
                void **argv2 = NULL;

                if (argc2 <= 8) {
                    for (int64_t i = 0; i < argc; i++) stack_args[i] = argv[i];
                    stack_args[argc] = block_val;
                    argv2 = stack_args;
                } else {
                    argv2 = (void **)ds_alloc(sizeof(void*) * (size_t)argc2);
                    for (int64_t i = 0; i < argc; i++) argv2[i] = argv[i];
                    argv2[argc] = block_val;
                }

                return ds_call_method(meth->func_ptr, receiver, argc2, argv2);
            }

            return ds_call_method(meth->func_ptr, receiver, argc, argv);
        }
        if (strcmp(method, "each") == 0 && block_val) {
            DSConstant *curr = cls->constants;
            void *args[1];
            while (curr) {
                args[0] = curr->value;
                dragonstone_runtime_block_invoke(block_val, 1, args);
                curr = curr->next;
            }
            return NULL;
        }
    }

    if (box->kind == DS_VALUE_INSTANCE) {
        DSInstance *inst = (DSInstance *)box->as.ptr;
        DSClass *cls = inst->klass;
        DSMethod *curr = ds_lookup_method_from(cls, method);
        if (curr) {
            if (curr->expects_block) {
                int64_t argc2 = argc + 1;
                void *stack_args[8];
                void **argv2 = NULL;

                if (argc2 <= 8) {
                    for (int64_t i = 0; i < argc; i++) stack_args[i] = argv[i];
                    stack_args[argc] = block_val;
                    argv2 = stack_args;
                } else {
                    argv2 = (void **)ds_alloc(sizeof(void*) * (size_t)argc2);
                    for (int64_t i = 0; i < argc; i++) argv2[i] = argv[i];
                    argv2[argc] = block_val;
                }

                return ds_call_method(curr->func_ptr, receiver, argc2, argv2);
            }

            return ds_call_method(curr->func_ptr, receiver, argc, argv);
        }
    }

    if (box->kind == DS_VALUE_ARRAY) {
        DSArray *arr = (DSArray *)box->as.ptr;
        if (strcmp(method, "length") == 0 || strcmp(method, "size") == 0) return (void *)dragonstone_runtime_box_i64(arr->length);
        if (strcmp(method, "first") == 0) return (arr->length > 0) ? arr->items[0] : NULL;
        if (strcmp(method, "last") == 0) return (arr->length > 0) ? arr->items[arr->length - 1] : NULL;
        if (strcmp(method, "empty") == 0 || strcmp(method, "empty?") == 0) return (void *)dragonstone_runtime_box_bool(arr->length == 0);
        if (strcmp(method, "inspect") == 0 || strcmp(method, "display") == 0) return dragonstone_runtime_value_display(receiver);
        if (strcmp(method, "pop") == 0) {
            if (arr->length == 0) return NULL;
            void *val = arr->items[arr->length - 1];
            arr->length--; 
            return val;
        }
        if (strcmp(method, "push") == 0 || strcmp(method, "<<") == 0) {
            if (argc > 0) dragonstone_runtime_array_push(receiver, argv[0]);
            return receiver;
        }
        if (strcmp(method, "each") == 0) {
            if (!block_val) return receiver;
            void *args[1];
            for (int64_t i = 0; i < arr->length; ++i) {
                args[0] = arr->items[i];
                dragonstone_runtime_block_invoke(block_val, 1, args);
            }
            return receiver;
        }
        if (strcmp(method, "select") == 0) {
            if (!block_val) return receiver;
            void **items = (void **)ds_alloc(sizeof(void*) * arr->length);
            int64_t count = 0;
            void *args[1];
            for (int64_t i = 0; i < arr->length; ++i) {
                args[0] = arr->items[i];
                void *result = dragonstone_runtime_block_invoke(block_val, 1, args);
                if (dragonstone_runtime_case_compare(result, dragonstone_runtime_box_bool(true))) {
                    items[count++] = arr->items[i];
                }
            }
            void *res = dragonstone_runtime_array_literal(count, items);
            free(items);
            return res;
        }
        if (strcmp(method, "inject") == 0) {
            if (!block_val) return receiver;
            if (argc > 1) return receiver;
            void *memo = argc == 1 ? argv[0] : NULL;
            void *args[2];
            for (int64_t i = 0; i < arr->length; ++i) {
                if (memo == NULL && argc == 0 && i == 0) {
                    memo = arr->items[i];
                    continue;
                }
                args[0] = memo;
                args[1] = arr->items[i];
                memo = dragonstone_runtime_block_invoke(block_val, 2, args);
            }
            return memo;
        }
        if (strcmp(method, "until") == 0) {
            if (!block_val) return receiver;
            void *args[1];
            for (int64_t i = 0; i < arr->length; ++i) {
                args[0] = arr->items[i];
                void *result = dragonstone_runtime_block_invoke(block_val, 1, args);
                if (dragonstone_runtime_case_compare(result, dragonstone_runtime_box_bool(true))) {
                    return arr->items[i];
                }
            }
            return NULL;
        }
    }

    if (box->kind == DS_VALUE_MAP) {
        DSMap *map = (DSMap *)box->as.ptr;
        if (strcmp(method, "length") == 0 || strcmp(method, "size") == 0) return (void *)dragonstone_runtime_box_i64(map->count);
        if (strcmp(method, "empty") == 0 || strcmp(method, "empty?") == 0) return (void *)dragonstone_runtime_box_bool(map->count == 0);
        if (strcmp(method, "inspect") == 0 || strcmp(method, "display") == 0) return dragonstone_runtime_value_display(receiver);
        
        if (strcmp(method, "keys") == 0) {
            void **buf = (void **)ds_alloc(sizeof(void*) * map->count);
            DSMapEntry *curr = map->head;
            int64_t i = 0;
            while (curr) { buf[i++] = curr->key; curr = curr->next; }
            void *res = dragonstone_runtime_array_literal(map->count, buf);
            free(buf);
            return res;
        }
        if (strcmp(method, "values") == 0) {
            void **buf = (void **)ds_alloc(sizeof(void*) * map->count);
            DSMapEntry *curr = map->head;
            int64_t i = 0;
            while (curr) { buf[i++] = curr->value; curr = curr->next; }
            void *res = dragonstone_runtime_array_literal(map->count, buf);
            free(buf);
            return res;
        }
        if (strcmp(method, "each") == 0) {
            if (!block_val) return receiver;
            void *args[2];
            DSMapEntry *curr = map->head;
            while (curr) {
                args[0] = curr->key;
                args[1] = curr->value;
                dragonstone_runtime_block_invoke(block_val, 2, args);
                curr = curr->next;
            }
            return receiver;
        }
        if (strcmp(method, "select") == 0) {
            if (!block_val) return receiver;
            DSMap *out = (DSMap *)ds_alloc(sizeof(DSMap));
            out->head = NULL;
            out->count = 0;
            DSMapEntry *curr = map->head;
            void *args[2];
            while (curr) {
                args[0] = curr->key;
                args[1] = curr->value;
                void *res = dragonstone_runtime_block_invoke(block_val, 2, args);
                if (dragonstone_runtime_case_compare(res, dragonstone_runtime_box_bool(true))) {
                    ds_map_append_entry(out, curr->key, curr->value);
                }
                curr = curr->next;
            }
            DSValue *box_out = ds_new_box(DS_VALUE_MAP);
            box_out->as.ptr = out;
            return box_out;
        }
        if (strcmp(method, "inject") == 0) {
            if (!block_val) return receiver;
            if (argc > 1) return receiver;
            void *memo = argc == 1 ? argv[0] : NULL;
            DSMapEntry *curr = map->head;
            void *args[3];
            while (curr) {
                if (memo == NULL && argc == 0) {
                    memo = curr->value;
                    curr = curr->next;
                    continue;
                }
                args[0] = memo;
                args[1] = curr->key;
                args[2] = curr->value;
                memo = dragonstone_runtime_block_invoke(block_val, 3, args);
                curr = curr->next;
            }
            return memo;
        }
        if (strcmp(method, "until") == 0) {
            if (!block_val) return receiver;
            void *args[2];
            DSMapEntry *curr = map->head;
            while (curr) {
                args[0] = curr->key;
                args[1] = curr->value;
                void *res = dragonstone_runtime_block_invoke(block_val, 2, args);
                if (dragonstone_runtime_case_compare(res, dragonstone_runtime_box_bool(true))) {
                    void **items = (void **)ds_alloc(sizeof(void*) * 2);
                    items[0] = curr->key;
                    items[1] = curr->value;
                    return dragonstone_runtime_tuple_literal(2, items);
                }
                curr = curr->next;
            }
            return NULL;
        }
    }

    if (box->kind == DS_VALUE_RANGE) {
        DSRange *rng = (DSRange *)box->as.ptr;

        int64_t start = rng->from;
        int64_t end = rng->exclusive ? rng->to - 1 : rng->to;

        if (strcmp(method, "first") == 0) {
            if (rng->is_char) {
                char buf[2] = { (char)rng->from, '\0' };
                return ds_strdup(buf);
            }
            return dragonstone_runtime_box_i64(rng->from);
        }

        if (strcmp(method, "last") == 0) {
            if (rng->is_char) {
                char buf[2] = { (char)rng->to, '\0' };
                return ds_strdup(buf);
            }
            return dragonstone_runtime_box_i64(rng->to);
        }

        if (strcmp(method, "includes?") == 0) {
            if (argc != 1) return dragonstone_runtime_box_bool(false);
            
            bool val_is_char = false;
            int64_t val = ds_get_ordinal(argv[0], &val_is_char);
            
            if (rng->is_char != val_is_char) return dragonstone_runtime_box_bool(false);

            bool yes = (val >= rng->from);
            if (yes) {
                if (rng->exclusive) yes = (val < rng->to);
                else yes = (val <= rng->to);
            }
            return dragonstone_runtime_box_bool(yes);
        }

        if (strcmp(method, "each") == 0) {
            if (!block_val) return receiver;
            int64_t current = start;
            void *args[1];

            int64_t limit = rng->to;
            
            while (current < limit || (!rng->exclusive && current == limit)) {
                if (rng->is_char) {
                    char buf[2] = { (char)current, '\0' };
                    args[0] = ds_strdup(buf);
                } else {
                    args[0] = dragonstone_runtime_box_i64(current);
                }
                dragonstone_runtime_block_invoke(block_val, 1, args);
                current++;
            }
            return receiver;
        }
        
        if (strcmp(method, "to_a") == 0) {
            int64_t count = 0;
            if (rng->exclusive) count = (rng->to > rng->from) ? (rng->to - rng->from) : 0;
            else count = (rng->to >= rng->from) ? (rng->to - rng->from + 1) : 0;
            
            if (count <= 0) return dragonstone_runtime_array_literal(0, NULL);

            void **items = (void **)ds_alloc(sizeof(void*) * (size_t)count);
            for (int64_t i = 0; i < count; i++) {
                if (rng->is_char) {
                    char buf[2] = { (char)(rng->from + i), '\0' };
                    items[i] = ds_strdup(buf);
                } else {
                    items[i] = dragonstone_runtime_box_i64(rng->from + i);
                }
            }
            void *res = dragonstone_runtime_array_literal(count, items);
            free(items);
            return res;
        }
    }

    fprintf(stderr, "[runtime] Method not found: %s\n", method);
    return NULL;
}

void *dragonstone_runtime_define_class(void *name_ptr) {
    const char *name = (const char *)name_ptr;
    DSClass *curr = global_classes;
    while (curr) {
        if (strcmp(curr->name, name) == 0) {
            if (curr->cached_box) return curr->cached_box;
            DSValue *box = ds_new_box(DS_VALUE_CLASS);
            box->as.ptr = curr;
            curr->cached_box = box;
            ds_constant_set(&global_constants, name, box);
            return box;
        }
        curr = curr->next;
    }
    DSClass *cls = (DSClass *)ds_alloc(sizeof(DSClass));
    cls->name = ds_strdup(name);
    cls->methods = NULL;
    cls->constants = NULL;
    cls->superclass = NULL;
    cls->next = global_classes;
    cls->is_module = false;
    global_classes = cls;
    
    DSValue *box = ds_new_box(DS_VALUE_CLASS);
    box->as.ptr = cls;
    cls->cached_box = box;
    
    ds_constant_set(&global_constants, name, box);
    return box;
}

void *dragonstone_runtime_define_module(void *name_ptr) {
    const char *name = (const char *)name_ptr;
    DSClass *curr = global_classes;
    while (curr) {
        if (strcmp(curr->name, name) == 0) {
            curr->is_module = true;
            if (curr->cached_box) return curr->cached_box;
            DSValue *box = ds_new_box(DS_VALUE_CLASS);
            box->as.ptr = curr;
            curr->cached_box = box;
            ds_constant_set(&global_constants, name, box);
            return box;
        }
        curr = curr->next;
    }
    DSClass *mod = (DSClass *)ds_alloc(sizeof(DSClass));
    mod->name = ds_strdup(name);
    mod->methods = NULL;
    mod->constants = NULL;
    mod->superclass = NULL;
    mod->next = global_classes;
    mod->is_module = true;
    global_classes = mod;
    
    DSValue *box = ds_new_box(DS_VALUE_CLASS);
    box->as.ptr = mod;
    mod->cached_box = box;
    
    ds_constant_set(&global_constants, name, box);
    return box;
}

void dragonstone_runtime_set_superclass(void *class_box_ptr, void *superclass_box_ptr) {
    if (!ds_is_boxed(class_box_ptr) || !ds_is_boxed(superclass_box_ptr)) return;
    DSValue *cbox = (DSValue *)class_box_ptr;
    DSValue *sbox = (DSValue *)superclass_box_ptr;
    if (cbox->kind != DS_VALUE_CLASS || sbox->kind != DS_VALUE_CLASS) return;
    DSClass *cls = (DSClass *)cbox->as.ptr;
    DSClass *sup = (DSClass *)sbox->as.ptr;
    cls->superclass = sup;
}

void *dragonstone_runtime_super_invoke(void *receiver, void *owner_class_box_ptr, void *method_name_ptr, int64_t argc, void **argv, void *block_val) {
    if (!ds_is_boxed(owner_class_box_ptr)) return NULL;
    DSValue *obox = (DSValue *)owner_class_box_ptr;
    if (obox->kind != DS_VALUE_CLASS) return NULL;

    DSClass *owner = (DSClass *)obox->as.ptr;
    DSClass *start = owner ? owner->superclass : NULL;
    const char *method = (const char *)method_name_ptr;
    if (!start || !method) return NULL;

    DSMethod *meth = ds_lookup_method_from(start, method);
    if (!meth) {
        fprintf(stderr, "[runtime] Super method not found: %s\n", method);
        return NULL;
    }

    if (meth->expects_block) {
        int64_t argc2 = argc + 1;
        void *stack_args[8];
        void **argv2 = NULL;

        if (argc2 <= 8) {
            for (int64_t i = 0; i < argc; i++) stack_args[i] = argv[i];
            stack_args[argc] = block_val;
            argv2 = stack_args;
        } else {
            argv2 = (void **)ds_alloc(sizeof(void*) * (size_t)argc2);
            for (int64_t i = 0; i < argc; i++) argv2[i] = argv[i];
            argv2[argc] = block_val;
        }

        return ds_call_method(meth->func_ptr, receiver, argc2, argv2);
    }

    return ds_call_method(meth->func_ptr, receiver, argc, argv);
}

void *dragonstone_runtime_root_self(void) {
    if (root_self_box) return root_self_box;

    DSValue *cls_box = (DSValue *)dragonstone_runtime_define_class((void *)"Object");
    if (!ds_is_boxed(cls_box)) return NULL;
    if (cls_box->kind != DS_VALUE_CLASS) return NULL;

    DSClass *cls = (DSClass *)cls_box->as.ptr;
    DSInstance *inst = (DSInstance *)ds_alloc(sizeof(DSInstance));
    inst->klass = cls;
    inst->ivars = NULL;

    DSValue *inst_box = ds_new_box(DS_VALUE_INSTANCE);
    inst_box->as.ptr = inst;
    root_self_box = inst_box;
    return root_self_box;
}

void dragonstone_runtime_extend(void *container_ptr, void *target_ptr) {
    if (!ds_is_boxed(container_ptr) || !ds_is_boxed(target_ptr)) return;
    DSValue *cbox = (DSValue *)container_ptr;
    DSValue *tbox = (DSValue *)target_ptr;
    if (cbox->kind != DS_VALUE_CLASS || tbox->kind != DS_VALUE_CLASS) return;

    DSClass *container = (DSClass *)cbox->as.ptr;
    DSClass *target = (DSClass *)tbox->as.ptr;
    DSMethod *meth = target->methods;
    while (meth) {
        bool duplicate = false;

        DSSingletonMethod *existing_singleton = singleton_methods;
        while (existing_singleton) {
            if (existing_singleton->receiver == container_ptr && strcmp(existing_singleton->name, meth->name) == 0) {
                duplicate = true;
                break;
            }
            existing_singleton = existing_singleton->next;
        }
        if (!duplicate) {
            DSSingletonMethod *node = (DSSingletonMethod *)ds_alloc(sizeof(DSSingletonMethod));
            node->receiver = container_ptr;
            node->name = ds_strdup(meth->name);
            node->func_ptr = meth->func_ptr;
            node->next = singleton_methods;
            singleton_methods = node;
        }

        DSMethod *cmeth = container->methods;
        duplicate = false;
        while (cmeth) {
            if (strcmp(cmeth->name, meth->name) == 0) {
                duplicate = true;
                break;
            }
            cmeth = cmeth->next;
        }
        if (!duplicate) {
            DSMethod *copy = (DSMethod *)ds_alloc(sizeof(DSMethod));
            copy->name = ds_strdup(meth->name);
            copy->func_ptr = meth->func_ptr;
            copy->next = container->methods;
            container->methods = copy;
        }
        meth = meth->next;
    }

    /* Some module methods are tracked only as singleton methods on the module object.
       Copy those too so `class X; extend M; end; X.foo` works under LLVM. */
    DSSingletonMethod *sm = singleton_methods;
    while (sm) {
        if (sm->receiver == target_ptr) {
            bool dup_singleton = false;
            DSSingletonMethod *existing = singleton_methods;
            while (existing) {
                if (existing->receiver == container_ptr && strcmp(existing->name, sm->name) == 0) {
                    dup_singleton = true;
                    break;
                }
                existing = existing->next;
            }
            if (!dup_singleton) {
                DSSingletonMethod *node = (DSSingletonMethod *)ds_alloc(sizeof(DSSingletonMethod));
                node->receiver = container_ptr;
                node->name = ds_strdup(sm->name);
                node->func_ptr = sm->func_ptr;
                node->next = singleton_methods;
                singleton_methods = node;
            }

            bool dup_method = false;
            DSMethod *cm = container->methods;
            while (cm) {
                if (strcmp(cm->name, sm->name) == 0) { dup_method = true; break; }
                cm = cm->next;
            }
            if (!dup_method) {
                DSMethod *copy = (DSMethod *)ds_alloc(sizeof(DSMethod));
                copy->name = ds_strdup(sm->name);
                copy->func_ptr = sm->func_ptr;
                copy->expects_block = false;
                copy->next = container->methods;
                container->methods = copy;
            }
        }
        sm = sm->next;
    }
}

void dragonstone_runtime_define_method(void *class_box_ptr, void *name_ptr, void *func_ptr, int32_t expects_block) {
    if (!ds_is_boxed(class_box_ptr)) return;
    DSValue *box = (DSValue *)class_box_ptr;
    if (box->kind != DS_VALUE_CLASS) return;
    DSClass *cls = (DSClass *)box->as.ptr;
    const char *method_name = (const char *)name_ptr;
    DSMethod *m = (DSMethod *)ds_alloc(sizeof(DSMethod));
    m->name = ds_strdup(method_name);
    m->func_ptr = func_ptr;
    m->expects_block = expects_block != 0;
    m->next = cls->methods;
    cls->methods = m;

    DSSingletonMethod *snode = (DSSingletonMethod *)ds_alloc(sizeof(DSSingletonMethod));
    snode->receiver = class_box_ptr;
    snode->name = ds_strdup(method_name);
    snode->func_ptr = func_ptr;
    snode->next = singleton_methods;
    singleton_methods = snode;
}

void dragonstone_runtime_define_enum_member(void *class_box_ptr, void *name_ptr, int64_t value) {
    if (!ds_is_boxed(class_box_ptr)) return;
    DSValue *box = (DSValue *)class_box_ptr;
    if (box->kind != DS_VALUE_CLASS) return;
    DSClass *cls = (DSClass *)box->as.ptr;
    char *name = (char *)name_ptr;

    DSEnum *e = (DSEnum *)ds_alloc(sizeof(DSEnum));
    e->klass = cls;
    e->value = value;
    e->name = ds_strdup(name);
    
    DSValue *val_box = ds_new_box(DS_VALUE_ENUM);
    val_box->as.ptr = e;
    
    DSConstant *c = (DSConstant *)ds_alloc(sizeof(DSConstant));
    c->name = ds_strdup(name);
    c->value = val_box;
    c->next = cls->constants;
    cls->constants = c;

    char *path = ds_join_path(cls->name, name);
    ds_constant_set(&global_constants, path, val_box);
}

void *dragonstone_runtime_constant_lookup(int64_t length, void **segments) {
    if (length <= 0) return NULL;
    size_t total_len = 0;
    for (int64_t i = 0; i < length; i++) {
        total_len += strlen((char *)segments[i]);
        if (i < length - 1) total_len += 2;
    }
    char *path = (char *)ds_alloc(total_len + 1);
    size_t offset = 0;
    for (int64_t i = 0; i < length; i++) {
        const char *seg = (const char *)segments[i];
        size_t seg_len = strlen(seg);
        memcpy(path + offset, seg, seg_len);
        offset += seg_len;
        if (i < length - 1) {
            path[offset++] = ':';
            path[offset++] = ':';
        }
    }
    path[offset] = '\0';

    void *val = ds_constant_get(global_constants, path);
    if (val) return val;

    const char *last_seg = (const char *)segments[length - 1];
    DSClass *curr = global_classes;
    while (curr) {
        if (strcmp(curr->name, path) == 0 || strcmp(curr->name, last_seg) == 0) {
            if (curr->cached_box) return curr->cached_box;
            DSValue *box = ds_new_box(DS_VALUE_CLASS);
            box->as.ptr = curr;
            curr->cached_box = box;
            return box;
        }
        curr = curr->next;
    }

    /* Fallback: if the backend passed a single "A::B" segment and it wasn't
       found, try resolving just "B" (Ruby-like constant fallback). */
    if (length == 1) {
        const char *seg0 = (const char *)segments[0];
        const char *tail = seg0;
        if (seg0) {
            const char *p = seg0;
            while (1) {
                const char *next = strstr(p, "::");
                if (!next) break;
                tail = next + 2;
                p = next + 2;
            }
        }
        if (tail && tail != seg0 && *tail != '\0') {
            void *tail_val = ds_constant_get(global_constants, tail);
            if (tail_val) return tail_val;

            DSClass *c = global_classes;
            while (c) {
                if (strcmp(c->name, tail) == 0) {
                    if (c->cached_box) return c->cached_box;
                    DSValue *box = ds_new_box(DS_VALUE_CLASS);
                    box->as.ptr = c;
                    c->cached_box = box;
                    return box;
                }
                c = c->next;
            }
        }
    }

    return NULL; 
}

void *dragonstone_runtime_value_display(void *value) { return ds_format_value(value, true); }
void *dragonstone_runtime_to_string(void *value) { return ds_value_to_string(value); }

static char *ds_debug_inline_source = NULL;
static char *ds_debug_inline_value = NULL;

static void ds_debug_append(char **buffer, const char *part) {
    if (!part) part = "";

    if (!*buffer) {
        *buffer = ds_strdup(part);
        return;
    }

    size_t lhs_len = strlen(*buffer);
    size_t rhs_len = strlen(part);
    size_t new_len = lhs_len + 3 + rhs_len + 1; /* " + " */
    char *next = (char *)ds_alloc(new_len);
    memcpy(next, *buffer, lhs_len);
    memcpy(next + lhs_len, " + ", 3);
    memcpy(next + lhs_len + 3, part, rhs_len);
    next[new_len - 1] = '\0';
    *buffer = next;
}

void dragonstone_runtime_debug_accum(void *source, void *value) {
    const char *source_str = source ? (const char *)source : "";
    char *value_str = (char *)dragonstone_runtime_value_display(value);
    ds_debug_append(&ds_debug_inline_source, source_str);
    ds_debug_append(&ds_debug_inline_value, value_str ? value_str : "");
}

void dragonstone_runtime_debug_flush(void) {
    if (!ds_debug_inline_source || !ds_debug_inline_value) return;

    printf("%s # -> %s\n", ds_debug_inline_source, ds_debug_inline_value);
    ds_debug_inline_source = NULL;
    ds_debug_inline_value = NULL;
}

void *dragonstone_runtime_typeof(void *value) {
    if (!value) return ds_strdup("Nil");
    if (!ds_is_boxed(value)) return ds_strdup("String");

    DSValue *box = (DSValue *)value;

    switch (box->kind) {
        case DS_VALUE_INT32:
        case DS_VALUE_INT64:
            return ds_strdup("Integer");
        case DS_VALUE_BOOL:
            return ds_strdup("Boolean");
        case DS_VALUE_FLOAT:
            return ds_strdup("Float");
        case DS_VALUE_STRUCT:
            return ds_strdup("Struct");
        case DS_VALUE_CLASS:
            return ds_strdup("Class");
        case DS_VALUE_INSTANCE: {
            DSInstance *inst = (DSInstance *)box->as.ptr;
            return ds_strdup(inst && inst->klass ? inst->klass->name : "Instance");
        }
        case DS_VALUE_ARRAY:
            return ds_strdup("Array");
        case DS_VALUE_MAP:
            return ds_strdup("Map");
        case DS_VALUE_BLOCK:
            return ds_strdup("Function");
        case DS_VALUE_RANGE:
            return ds_strdup("Range");
        case DS_VALUE_TUPLE:
            return ds_strdup("Tuple");
        case DS_VALUE_NAMED_TUPLE:
            return ds_strdup("NamedTuple");
        case DS_VALUE_ENUM:
            return ds_strdup("Enum");
        case DS_VALUE_BAG_CONSTRUCTOR:
            return ds_strdup("BagConstructor");
        case DS_VALUE_BAG:
            return ds_strdup("Bag");
        default:
            return ds_strdup("Object");
    }
}

void *dragonstone_runtime_ivar_get(void *obj, void *name) {
    if (!ds_is_boxed(obj)) return NULL;
    DSValue *box = (DSValue *)obj;
    if (box->kind != DS_VALUE_INSTANCE) return NULL;
    DSInstance *inst = (DSInstance *)box->as.ptr;
    if (!inst->ivars) return NULL;

    const char *name_str = ds_arg_string(name);
    if (!name_str) return NULL;

    DSMapEntry *curr = inst->ivars->head;
    while (curr) {
        if (strcmp((char *)curr->key, name_str) == 0) return curr->value;
        curr = curr->next;
    }
    return NULL;
}

void *dragonstone_runtime_ivar_set(void *obj, void *name, void *val) {
    if (!ds_is_boxed(obj)) return val;
    DSValue *box = (DSValue *)obj;
    if (box->kind != DS_VALUE_INSTANCE) return val;
    DSInstance *inst = (DSInstance *)box->as.ptr;

    const char *name_str = ds_arg_string(name);
    if (!name_str) return val;

    if (!inst->ivars) {
        inst->ivars = (DSMap *)ds_alloc(sizeof(DSMap));
        inst->ivars->head = NULL;
        inst->ivars->count = 0;
    }

    DSMapEntry *curr = inst->ivars->head;
    while (curr) {
        if (strcmp((char *)curr->key, name_str) == 0) {
            curr->value = val;
            return val;
        }
        curr = curr->next;
    }

    ds_map_append_entry(inst->ivars, ds_strdup(name_str), val);
    return val;
}

void *dragonstone_runtime_interpolated_string(int64_t length, void **segments) {
    if (length <= 0) return ds_strdup("");
    size_t total_len = 0;
    for (int64_t i = 0; i < length; ++i) {
        if (segments[i]) total_len += strlen((const char*)segments[i]);
    }
    char *result = (char *)ds_alloc(total_len + 1);
    char *cursor = result;
    for (int64_t i = 0; i < length; ++i) {
        if (segments[i]) {
            size_t len = strlen((const char*)segments[i]);
            memcpy(cursor, segments[i], len);
            cursor += len;
        }
    }
    *cursor = '\0';
    return result;
}

_Bool dragonstone_runtime_case_compare(void *lhs, void *rhs) {
    if (lhs == rhs) return true;
    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *left = (DSValue *)lhs;
        DSValue *right = (DSValue *)rhs;
        if (left->kind != right->kind) return false;
        switch (left->kind) {
            case DS_VALUE_INT32: return left->as.i32 == right->as.i32;
            case DS_VALUE_INT64: return left->as.i64 == right->as.i64;
            case DS_VALUE_FLOAT: return left->as.f64 == right->as.f64;
            case DS_VALUE_BOOL:  return left->as.boolean == right->as.boolean;
            case DS_VALUE_ARRAY: return left->as.ptr == right->as.ptr;
            case DS_VALUE_INSTANCE: return left->as.ptr == right->as.ptr;
            case DS_VALUE_CLASS: return left->as.ptr == right->as.ptr;
            case DS_VALUE_MAP: return left->as.ptr == right->as.ptr;
            case DS_VALUE_RANGE: {
                DSRange *l = (DSRange *)left->as.ptr;
                DSRange *r = (DSRange *)right->as.ptr;
                return l->from == r->from && l->to == r->to && l->exclusive == r->exclusive;
            }
            default: return false;
        }
    }
    if (!ds_is_boxed(lhs) && !ds_is_boxed(rhs)) {
        if (!lhs || !rhs) return false;
        return strcmp((const char*)lhs, (const char*)rhs) == 0;
    }
    if (ds_is_boxed(lhs) && !ds_is_boxed(rhs)) {
        return false; 
    }
    
    return false;
}

void dragonstone_runtime_set_argv(int64_t argc, char **argv) {
    dragonstone_io_set_argv(argc, argv);
    ds_program_argv_box = NULL;
}

void *dragonstone_runtime_argv(void) {
    if (ds_program_argv_box) return ds_program_argv_box;

    int64_t count = dragonstone_io_argc();
    const char **argv = dragonstone_io_argv();

    DSArray *array = (DSArray *)ds_alloc(sizeof(DSArray));
    array->length = count;
    array->items = count > 0 ? (void **)ds_alloc(sizeof(void *) * (size_t)count) : NULL;

    for (int64_t i = 0; i < count; ++i) {
        array->items[i] = ds_strdup(argv[i]);
    }

    DSValue *box = ds_new_box(DS_VALUE_ARRAY);
    box->as.ptr = array;

    ds_program_argv_box = box;
    return box;
}

void *dragonstone_runtime_argc(void) {
    return dragonstone_runtime_box_i64(dragonstone_io_argc());
}

static void *ds_make_instance(void *class_box_ptr) {
    if (!ds_is_boxed(class_box_ptr)) return NULL;
    DSValue *cbox = (DSValue *)class_box_ptr;
    if (cbox->kind != DS_VALUE_CLASS) return NULL;
    DSClass *cls = (DSClass *)cbox->as.ptr;
    DSInstance *inst = (DSInstance *)ds_alloc(sizeof(DSInstance));
    inst->klass = cls;
    inst->ivars = NULL;
    DSValue *inst_box = ds_new_box(DS_VALUE_INSTANCE);
    inst_box->as.ptr = inst;
    return inst_box;
}

static void ds_stream_write(bool is_err, const char *text) {
    if (!text) return;
    size_t len = strlen(text);
    if (len == 0) return;
    if (is_err) {
        dragonstone_io_write_stderr((const uint8_t *)text, len);
    } else {
        dragonstone_io_write_stdout((const uint8_t *)text, len);
    }
}

static void *ds_iostream_eecholn(void *receiver, void *value) {
    bool is_err = receiver == ds_builtin_stderr;
    void *str_ptr = value;
    if (str_ptr && ds_is_boxed(str_ptr)) str_ptr = dragonstone_runtime_to_string(str_ptr);
    ds_stream_write(is_err, (const char *)str_ptr);
    return NULL;
}

static void *ds_iostream_echoln(void *receiver, void *value) {
    bool is_err = receiver == ds_builtin_stderr;
    void *str_ptr = value;
    if (str_ptr && ds_is_boxed(str_ptr)) str_ptr = dragonstone_runtime_to_string(str_ptr);
    ds_stream_write(is_err, (const char *)str_ptr);
    ds_stream_write(is_err, "\n");
    return NULL;
}

static void *ds_iostream_debug(void *receiver, void *value) {
    return ds_iostream_echoln(receiver, value);
}

static void *ds_iostream_debug_inline(void *receiver, void *value) {
    return ds_iostream_eecholn(receiver, value);
}

static void *ds_iostream_flush(void *receiver) {
    bool is_err = receiver == ds_builtin_stderr;
    if (is_err) {
        dragonstone_io_flush_stderr();
    } else {
        dragonstone_io_flush_stdout();
    }
    return NULL;
}

static void *ds_stdin_read(void *receiver) {
    (void)receiver;
    return dragonstone_io_read_stdin_line();
}

static void *ds_argf_read(void *receiver) {
    (void)receiver;
    return dragonstone_io_read_argf();
}

static void ds_init_io_builtins(void) {
    if (ds_io_builtins_initialized) return;

    ds_builtin_io_stream_class = dragonstone_runtime_define_class((void *)"IOStream");
    dragonstone_runtime_define_method(ds_builtin_io_stream_class, (void *)"eecholn", (void *)&ds_iostream_eecholn, 0);
    dragonstone_runtime_define_method(ds_builtin_io_stream_class, (void *)"echoln", (void *)&ds_iostream_echoln, 0);
    dragonstone_runtime_define_method(ds_builtin_io_stream_class, (void *)"debug", (void *)&ds_iostream_debug, 0);
    dragonstone_runtime_define_method(ds_builtin_io_stream_class, (void *)"debug_inline", (void *)&ds_iostream_debug_inline, 0);
    dragonstone_runtime_define_method(ds_builtin_io_stream_class, (void *)"flush", (void *)&ds_iostream_flush, 0);

    ds_builtin_stdout = ds_make_instance(ds_builtin_io_stream_class);
    ds_builtin_stderr = ds_make_instance(ds_builtin_io_stream_class);

    ds_builtin_stdin_class = dragonstone_runtime_define_class((void *)"StandardInput");
    dragonstone_runtime_define_method(ds_builtin_stdin_class, (void *)"read", (void *)&ds_stdin_read, 0);
    ds_builtin_stdin = ds_make_instance(ds_builtin_stdin_class);

    ds_builtin_argf_class = dragonstone_runtime_define_class((void *)"ARGF");
    dragonstone_runtime_define_method(ds_builtin_argf_class, (void *)"read", (void *)&ds_argf_read, 0);
    ds_builtin_argf = ds_make_instance(ds_builtin_argf_class);

    ds_io_builtins_initialized = true;
}

void *dragonstone_runtime_stdout(void) {
    ds_init_io_builtins();
    return ds_builtin_stdout;
}

void *dragonstone_runtime_stderr(void) {
    ds_init_io_builtins();
    return ds_builtin_stderr;
}

void *dragonstone_runtime_stdin(void) {
    ds_init_io_builtins();
    return ds_builtin_stdin;
}

void *dragonstone_runtime_argf(void) {
    ds_init_io_builtins();
    return ds_builtin_argf;
}

void *dragonstone_runtime_array_literal(int64_t length, void **elements) { return ds_create_array_box(length, elements); }
void *dragonstone_runtime_map_literal(int64_t length, void **keys, void **values) { return ds_create_map_box(length, keys, values); }

void *dragonstone_runtime_range_literal(void *from_ptr, void *to_ptr, bool exclusive) {
    DSRange *rng = (DSRange *)ds_alloc(sizeof(DSRange));
    
    bool from_char = false;
    bool to_char = false;
    
    rng->from = ds_get_ordinal(from_ptr, &from_char);
    rng->to = ds_get_ordinal(to_ptr, &to_char);
    rng->exclusive = exclusive;
    rng->is_char = from_char && to_char;
    
    DSValue *box = ds_new_box(DS_VALUE_RANGE);
    box->as.ptr = rng;
    return box;
}

void *dragonstone_runtime_index_get(void *object, void *index_value) {
    if (!ds_is_boxed(object)) return NULL;
    DSValue *obj_box = (DSValue *)object;

    if (obj_box->kind == DS_VALUE_TUPLE) {
        DSTuple *tuple = (DSTuple *)obj_box->as.ptr;
        int64_t idx = dragonstone_runtime_unbox_i64(index_value);
        if (idx < 0 || idx >= tuple->length) return NULL;
        return tuple->items[idx];
    }

    if (obj_box->kind == DS_VALUE_NAMED_TUPLE) {
        DSNamedTuple *nt = (DSNamedTuple *)obj_box->as.ptr;
        char *key = (char *)index_value;
        if (ds_is_boxed(index_value)) return NULL;

        for (int64_t i = 0; i < nt->length; i++) {
            if (strcmp(nt->keys[i], key) == 0) {
                return nt->values[i];
            }
        }
        return NULL;
    }

    if (obj_box->kind == DS_VALUE_ARRAY) {
        DSArray *array = (DSArray *)obj_box->as.ptr;
        int64_t idx = 0;
        if (ds_is_boxed(index_value)) {
            DSValue *ibox = (DSValue *)index_value;
            if (ibox->kind == DS_VALUE_INT32) idx = ibox->as.i32;
            else if (ibox->kind == DS_VALUE_INT64) idx = ibox->as.i64;
            else return NULL;
        } else return NULL;

        if (idx < 0) idx = array->length + idx;
        if (idx < 0 || idx >= array->length) return NULL;
        return array->items[idx];
    }

    if (obj_box->kind == DS_VALUE_MAP) {
        DSMap *map = (DSMap *)obj_box->as.ptr;
        DSMapEntry *curr = map->head;
        while (curr) {
            if (dragonstone_runtime_case_compare(curr->key, index_value)) {
                return curr->value;
            }
            curr = curr->next;
        }
        return NULL;
    }

    return NULL;
}

void *dragonstone_runtime_index_set(void *object, void *index_value, void *value) {
    if (!ds_is_boxed(object)) return value;
    DSValue *obj_box = (DSValue *)object;

    if (obj_box->kind == DS_VALUE_ARRAY) {
        DSArray *array = (DSArray *)obj_box->as.ptr;
        int64_t idx = 0;
        if (ds_is_boxed(index_value)) {
            DSValue *ibox = (DSValue *)index_value;
            if (ibox->kind == DS_VALUE_INT32) idx = ibox->as.i32;
            else if (ibox->kind == DS_VALUE_INT64) idx = ibox->as.i64;
            else return value;
        } else return value;

        if (idx < 0) idx = array->length + idx;
        if (idx >= array->length) {
            int64_t new_len = idx + 1;
            void **new_items = (void **)realloc(array->items, sizeof(void*) * new_len);
            if (!new_items) abort();
            for (int64_t i = array->length; i < new_len; i++) new_items[i] = NULL;
            array->items = new_items;
            array->length = new_len;
        }
        if (idx >= 0) array->items[idx] = value;
        return value;
    }

    if (obj_box->kind == DS_VALUE_MAP) {
        DSMap *map = (DSMap *)obj_box->as.ptr;
        DSMapEntry *curr = map->head;
        while (curr) {
            if (dragonstone_runtime_case_compare(curr->key, index_value)) {
                curr->value = value;
                return value;
            }
            curr = curr->next;
        }
        ds_map_append_entry(map, index_value, value);
        return value;
    }

    return value;
}

void *dragonstone_runtime_tuple_literal(int64_t l, void **e) {
    DSTuple *tup = (DSTuple *)ds_alloc(sizeof(DSTuple));
    tup->length = l;
    tup->items = e;
    DSValue *box = ds_new_box(DS_VALUE_TUPLE);
    box->as.ptr = tup;
    return box;
}

void *dragonstone_runtime_named_tuple_literal(int64_t l, void **k, void **v) {
    DSNamedTuple *nt = (DSNamedTuple *)ds_alloc(sizeof(DSNamedTuple));
    nt->length = l;
    nt->keys = (char **)k;
    nt->values = v;
    DSValue *box = ds_new_box(DS_VALUE_NAMED_TUPLE);
    box->as.ptr = nt;
    return box;
}

void *dragonstone_runtime_bag_constructor(void *element_type) {
    DSBagConstructor *ctor = (DSBagConstructor *)ds_alloc(sizeof(DSBagConstructor));
    ctor->element_type = element_type ? ds_strdup((char *)element_type) : ds_strdup("dynamic");
    DSValue *box = ds_new_box(DS_VALUE_BAG_CONSTRUCTOR);
    box->as.ptr = ctor;
    return box;
}

void *dragonstone_runtime_add(void *lhs, void *rhs) {
    int lhs_boxed = ds_is_boxed(lhs);
    int rhs_boxed = ds_is_boxed(rhs);

    if (lhs_boxed) {
        DSValue *l = (DSValue *)lhs;

        if (l->kind == DS_VALUE_INSTANCE) {
            DSInstance *inst = (DSInstance *)l->as.ptr;
            DSMethod *meth = inst && inst->klass ? ds_lookup_method_from(inst->klass, "+") : NULL;
            if (!meth) {
                dragonstone_runtime_raise("Unsupported operands for +");
                return NULL;
            }
            void *args[1];
            args[0] = rhs;
            if (meth->expects_block) {
                void *argv2[2];
                argv2[0] = rhs;
                argv2[1] = NULL;
                return ds_call_method(meth->func_ptr, lhs, 2, argv2);
            }
            return ds_call_method(meth->func_ptr, lhs, 1, args);
        }

        if (l->kind == DS_VALUE_CLASS) {
            DSClass *cls = (DSClass *)l->as.ptr;
            DSMethod *meth = cls ? ds_lookup_method_from(cls, "+") : NULL;
            if (!meth) {
                dragonstone_runtime_raise("Unsupported operands for +");
                return NULL;
            }
            void *args[1];
            args[0] = rhs;
            if (meth->expects_block) {
                void *argv2[2];
                argv2[0] = rhs;
                argv2[1] = NULL;
                return ds_call_method(meth->func_ptr, lhs, 2, argv2);
            }
            return ds_call_method(meth->func_ptr, lhs, 1, args);
        }

        if (lhs_boxed && rhs_boxed) {
            DSValue *r = (DSValue *)rhs;

            if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
                (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
                int64_t li = (l->kind == DS_VALUE_INT32) ? l->as.i32 : l->as.i64;
                int64_t ri = (r->kind == DS_VALUE_INT32) ? r->as.i32 : r->as.i64;
                return dragonstone_runtime_box_i64(li + ri);
            }

            if (l->kind == DS_VALUE_FLOAT && r->kind == DS_VALUE_FLOAT) {
                double res = l->as.f64 + r->as.f64;
                return dragonstone_runtime_box_float(res);
            }
        }

        dragonstone_runtime_raise("Unsupported operands for +");
        return NULL;
    }

    /* String concatenation (only when LHS is a string / unboxed value). */
    char *lhs_str = (char *)dragonstone_runtime_to_string(lhs);
    char *rhs_str = (char *)dragonstone_runtime_to_string(rhs);

    size_t lhs_len = lhs_str ? strlen(lhs_str) : 0;
    size_t rhs_len = rhs_str ? strlen(rhs_str) : 0;
    char *result = (char *)ds_alloc(lhs_len + rhs_len + 1);
    if (lhs_len > 0) memcpy(result, lhs_str, lhs_len);
    if (rhs_len > 0) memcpy(result + lhs_len, rhs_str, rhs_len);
    result[lhs_len + rhs_len] = '\0';
    return result;
}

void *dragonstone_runtime_negate(void *value) {
    if (ds_is_boxed(value)) {
        DSValue *v = (DSValue *)value;
        if (v->kind == DS_VALUE_INT32) {
            return dragonstone_runtime_box_i64(-(int64_t)v->as.i32);
        }
        if (v->kind == DS_VALUE_INT64) {
            return dragonstone_runtime_box_i64(-v->as.i64);
        }
        if (v->kind == DS_VALUE_FLOAT) {
            return dragonstone_runtime_box_float(-v->as.f64);
        }
    }

    dragonstone_runtime_raise("Cannot apply unary minus");
    return NULL;
}

void **dragonstone_runtime_block_env_allocate(int64_t l) { return calloc(l, sizeof(void*)); }
void dragonstone_runtime_rescue_placeholder(void) { abort(); }
void *dragonstone_runtime_define_constant(void *n, void *v) {
    const char *name = (const char *)n;
    ds_constant_set(&global_constants, name, v);
    return v;
}
void dragonstone_runtime_yield_missing_block(void) { abort(); }
void dragonstone_runtime_extend_container(void *c, void *t) { dragonstone_runtime_extend(c, t); }

static void *ds_box_truthy(void *value) {
    return dragonstone_runtime_box_bool(dragonstone_runtime_is_truthy(value) ? 1 : 0);
}

static void *ds_try_invoke_operator(void *lhs, const char *op, void *rhs) {
    if (!lhs || !ds_is_boxed(lhs) || !op) return NULL;

    DSValue *lbox = (DSValue *)lhs;
    DSClass *cls = NULL;

    if (lbox->kind == DS_VALUE_INSTANCE) {
        DSInstance *inst = (DSInstance *)lbox->as.ptr;
        cls = inst ? inst->klass : NULL;
    } else if (lbox->kind == DS_VALUE_CLASS) {
        cls = (DSClass *)lbox->as.ptr;
    } else {
        return NULL;
    }

    if (!cls) return NULL;
    DSMethod *meth = ds_lookup_method_from(cls, op);
    if (!meth) return NULL;

    if (meth->expects_block) {
        void *argv2[2];
        argv2[0] = rhs;
        argv2[1] = NULL;
        return ds_call_method(meth->func_ptr, lhs, 2, argv2);
    }

    void *args[1];
    args[0] = rhs;
    return ds_call_method(meth->func_ptr, lhs, 1, args);
}

void *dragonstone_runtime_sub(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, "-", rhs);
    if (over) return over;

    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *l = (DSValue *)lhs;
        DSValue *r = (DSValue *)rhs;

        if (l->kind == DS_VALUE_FLOAT || r->kind == DS_VALUE_FLOAT) {
            double ld = dragonstone_runtime_unbox_float(lhs);
            double rd = dragonstone_runtime_unbox_float(rhs);
            return dragonstone_runtime_box_float(ld - rd);
        }

        if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
            (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
            int64_t li = (l->kind == DS_VALUE_INT32) ? l->as.i32 : l->as.i64;
            int64_t ri = (r->kind == DS_VALUE_INT32) ? r->as.i32 : r->as.i64;
            return dragonstone_runtime_box_i64(li - ri);
        }
    }

    dragonstone_runtime_raise("Unsupported operands for -");
    return NULL;
}

void *dragonstone_runtime_mul(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, "*", rhs);
    if (over) return over;

    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *l = (DSValue *)lhs;
        DSValue *r = (DSValue *)rhs;

        if (l->kind == DS_VALUE_FLOAT || r->kind == DS_VALUE_FLOAT) {
            double ld = dragonstone_runtime_unbox_float(lhs);
            double rd = dragonstone_runtime_unbox_float(rhs);
            return dragonstone_runtime_box_float(ld * rd);
        }

        if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
            (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
            int64_t li = (l->kind == DS_VALUE_INT32) ? l->as.i32 : l->as.i64;
            int64_t ri = (r->kind == DS_VALUE_INT32) ? r->as.i32 : r->as.i64;
            return dragonstone_runtime_box_i64(li * ri);
        }
    }

    dragonstone_runtime_raise("Unsupported operands for *");
    return NULL;
}

void *dragonstone_runtime_div(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, "/", rhs);
    if (over) return over;

    if (ds_is_boxed(rhs)) {
        DSValue *r = (DSValue *)rhs;
        if ((r->kind == DS_VALUE_INT32 && r->as.i32 == 0) || (r->kind == DS_VALUE_INT64 && r->as.i64 == 0) || (r->kind == DS_VALUE_FLOAT && r->as.f64 == 0.0)) {
            dragonstone_runtime_raise("Division by zero");
            return NULL;
        }
    }

    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *l = (DSValue *)lhs;
        DSValue *r = (DSValue *)rhs;

        if (l->kind == DS_VALUE_FLOAT || r->kind == DS_VALUE_FLOAT) {
            double ld = dragonstone_runtime_unbox_float(lhs);
            double rd = dragonstone_runtime_unbox_float(rhs);
            return dragonstone_runtime_box_float(ld / rd);
        }

        if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
            (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
            double ld = (l->kind == DS_VALUE_INT32) ? (double)l->as.i32 : (double)l->as.i64;
            double rd = (r->kind == DS_VALUE_INT32) ? (double)r->as.i32 : (double)r->as.i64;
            return dragonstone_runtime_box_float(ld / rd);
        }
    }

    dragonstone_runtime_raise("Unsupported operands for /");
    return NULL;
}

void *dragonstone_runtime_mod(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, "%", rhs);
    if (over) return over;

    if (ds_is_boxed(rhs)) {
        DSValue *r = (DSValue *)rhs;
        if ((r->kind == DS_VALUE_INT32 && r->as.i32 == 0) || (r->kind == DS_VALUE_INT64 && r->as.i64 == 0) || (r->kind == DS_VALUE_FLOAT && r->as.f64 == 0.0)) {
            dragonstone_runtime_raise("Division by zero");
            return NULL;
        }
    }

    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *l = (DSValue *)lhs;
        DSValue *r = (DSValue *)rhs;

        if (l->kind == DS_VALUE_FLOAT || r->kind == DS_VALUE_FLOAT) {
            double ld = dragonstone_runtime_unbox_float(lhs);
            double rd = dragonstone_runtime_unbox_float(rhs);
            return dragonstone_runtime_box_float(fmod(ld, rd));
        }

        if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
            (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
            int64_t li = (l->kind == DS_VALUE_INT32) ? l->as.i32 : l->as.i64;
            int64_t ri = (r->kind == DS_VALUE_INT32) ? r->as.i32 : r->as.i64;
            return dragonstone_runtime_box_i64(li % ri);
        }
    }

    dragonstone_runtime_raise("Unsupported operands for %");
    return NULL;
}

static int64_t ds_int_floor_div(int64_t lhs, int64_t rhs) {
    int64_t q = lhs / rhs;
    int64_t r = lhs % rhs;
    if (r != 0 && ((r > 0) != (rhs > 0))) {
        q -= 1;
    }
    return q;
}

static int64_t ds_int_pow_i64(int64_t base, int64_t exp) {
    int64_t result = 1;
    int64_t factor = base;
    int64_t power = exp;
    while (power > 0) {
        if ((power & 1) == 1) result *= factor;
        power >>= 1;
        if (power == 0) break;
        factor *= factor;
    }
    return result;
}

void *dragonstone_runtime_shl(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, "<<", rhs);
    if (over) return over;

    if (ds_is_boxed(lhs)) {
        DSValue *l = (DSValue *)lhs;
        if (l->kind == DS_VALUE_ARRAY) {
            dragonstone_runtime_array_push(lhs, rhs);
            return lhs;
        }
    }

    int64_t li = dragonstone_runtime_unbox_i64(lhs);
    int64_t ri = dragonstone_runtime_unbox_i64(rhs);
    return dragonstone_runtime_box_i64(li << ri);
}

void *dragonstone_runtime_shr(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, ">>", rhs);
    if (over) return over;

    int64_t li = dragonstone_runtime_unbox_i64(lhs);
    int64_t ri = dragonstone_runtime_unbox_i64(rhs);
    return dragonstone_runtime_box_i64(li >> ri);
}

void *dragonstone_runtime_floor_div(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, "//", rhs);
    if (over) return over;

    if (ds_is_boxed(rhs)) {
        DSValue *r = (DSValue *)rhs;
        if ((r->kind == DS_VALUE_INT32 && r->as.i32 == 0) || (r->kind == DS_VALUE_INT64 && r->as.i64 == 0) || (r->kind == DS_VALUE_FLOAT && r->as.f64 == 0.0)) {
            dragonstone_runtime_raise("Division by zero");
            return NULL;
        }
    }

    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *l = (DSValue *)lhs;
        DSValue *r = (DSValue *)rhs;

        if (l->kind == DS_VALUE_FLOAT || r->kind == DS_VALUE_FLOAT) {
            double ld = dragonstone_runtime_unbox_float(lhs);
            double rd = dragonstone_runtime_unbox_float(rhs);
            return dragonstone_runtime_box_float(floor(ld / rd));
        }

        if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
            (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
            int64_t li = (l->kind == DS_VALUE_INT32) ? l->as.i32 : l->as.i64;
            int64_t ri = (r->kind == DS_VALUE_INT32) ? r->as.i32 : r->as.i64;
            return dragonstone_runtime_box_i64(ds_int_floor_div(li, ri));
        }
    }

    dragonstone_runtime_raise("Unsupported operands for //");
    return NULL;
}

void *dragonstone_runtime_pow(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, "**", rhs);
    if (over) return over;

    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *l = (DSValue *)lhs;
        DSValue *r = (DSValue *)rhs;

        if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
            (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
            int64_t base = (l->kind == DS_VALUE_INT32) ? l->as.i32 : l->as.i64;
            int64_t exp = (r->kind == DS_VALUE_INT32) ? r->as.i32 : r->as.i64;
            if (exp >= 0) {
                return dragonstone_runtime_box_i64(ds_int_pow_i64(base, exp));
            }
            return dragonstone_runtime_box_float(pow((double)base, (double)exp));
        }

        if (l->kind == DS_VALUE_FLOAT || r->kind == DS_VALUE_FLOAT) {
            double ld = dragonstone_runtime_unbox_float(lhs);
            double rd = dragonstone_runtime_unbox_float(rhs);
            return dragonstone_runtime_box_float(pow(ld, rd));
        }
    }

    dragonstone_runtime_raise("Unsupported operands for **");
    return NULL;
}

void *dragonstone_runtime_cmp(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, "<=>", rhs);
    if (over) return over;

    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *l = (DSValue *)lhs;
        DSValue *r = (DSValue *)rhs;

        if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
            (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
            int64_t li = (l->kind == DS_VALUE_INT32) ? l->as.i32 : l->as.i64;
            int64_t ri = (r->kind == DS_VALUE_INT32) ? r->as.i32 : r->as.i64;
            return dragonstone_runtime_box_i64(li < ri ? -1 : (li > ri ? 1 : 0));
        }

        if (l->kind == DS_VALUE_FLOAT || r->kind == DS_VALUE_FLOAT) {
            double ld = dragonstone_runtime_unbox_float(lhs);
            double rd = dragonstone_runtime_unbox_float(rhs);
            return dragonstone_runtime_box_i64(ld < rd ? -1 : (ld > rd ? 1 : 0));
        }
    }

    if (!ds_is_boxed(lhs) && !ds_is_boxed(rhs) && lhs && rhs) {
        int cmp = strcmp((char *)lhs, (char *)rhs);
        return dragonstone_runtime_box_i64(cmp < 0 ? -1 : (cmp > 0 ? 1 : 0));
    }

    return dragonstone_runtime_box_i64(0);
}

void *dragonstone_runtime_gt(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, ">", rhs);
    if (over) return ds_is_boxed(over) && ((DSValue *)over)->kind == DS_VALUE_BOOL ? over : ds_box_truthy(over);

    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *l = (DSValue *)lhs;
        DSValue *r = (DSValue *)rhs;
        
        if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
            (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
            int64_t li = (l->kind == DS_VALUE_INT32) ? l->as.i32 : l->as.i64;
            int64_t ri = (r->kind == DS_VALUE_INT32) ? r->as.i32 : r->as.i64;
            return dragonstone_runtime_box_bool(li > ri);
        }
        
        if (l->kind == DS_VALUE_FLOAT || r->kind == DS_VALUE_FLOAT) {
            double ld = dragonstone_runtime_unbox_float(lhs);
            double rd = dragonstone_runtime_unbox_float(rhs);
            return dragonstone_runtime_box_bool(ld > rd);
        }
    }
    
    if (!ds_is_boxed(lhs) && !ds_is_boxed(rhs)) {
        return dragonstone_runtime_box_bool(strcmp((char*)lhs, (char*)rhs) > 0);
    }
    
    return dragonstone_runtime_box_bool(false);
}

void *dragonstone_runtime_lt(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, "<", rhs);
    if (over) return ds_is_boxed(over) && ((DSValue *)over)->kind == DS_VALUE_BOOL ? over : ds_box_truthy(over);

    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *l = (DSValue *)lhs;
        DSValue *r = (DSValue *)rhs;
        
        if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
            (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
            int64_t li = (l->kind == DS_VALUE_INT32) ? l->as.i32 : l->as.i64;
            int64_t ri = (r->kind == DS_VALUE_INT32) ? r->as.i32 : r->as.i64;
            return dragonstone_runtime_box_bool(li < ri);
        }
        
        if (l->kind == DS_VALUE_FLOAT || r->kind == DS_VALUE_FLOAT) {
            double ld = dragonstone_runtime_unbox_float(lhs);
            double rd = dragonstone_runtime_unbox_float(rhs);
            return dragonstone_runtime_box_bool(ld < rd);
        }
    }
    
    if (!ds_is_boxed(lhs) && !ds_is_boxed(rhs)) {
        return dragonstone_runtime_box_bool(strcmp((char*)lhs, (char*)rhs) < 0);
    }
    
    return dragonstone_runtime_box_bool(false);
}

void *dragonstone_runtime_gte(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, ">=", rhs);
    if (over) return ds_is_boxed(over) && ((DSValue *)over)->kind == DS_VALUE_BOOL ? over : ds_box_truthy(over);

    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *l = (DSValue *)lhs;
        DSValue *r = (DSValue *)rhs;
        
        if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
            (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
            int64_t li = (l->kind == DS_VALUE_INT32) ? l->as.i32 : l->as.i64;
            int64_t ri = (r->kind == DS_VALUE_INT32) ? r->as.i32 : r->as.i64;
            return dragonstone_runtime_box_bool(li >= ri);
        }
        
        if (l->kind == DS_VALUE_FLOAT || r->kind == DS_VALUE_FLOAT) {
            double ld = dragonstone_runtime_unbox_float(lhs);
            double rd = dragonstone_runtime_unbox_float(rhs);
            return dragonstone_runtime_box_bool(ld >= rd);
        }
    }
    
    if (!ds_is_boxed(lhs) && !ds_is_boxed(rhs)) {
        return dragonstone_runtime_box_bool(strcmp((char*)lhs, (char*)rhs) >= 0);
    }
    
    return dragonstone_runtime_box_bool(false);
}

void *dragonstone_runtime_lte(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, "<=", rhs);
    if (over) return ds_is_boxed(over) && ((DSValue *)over)->kind == DS_VALUE_BOOL ? over : ds_box_truthy(over);

    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *l = (DSValue *)lhs;
        DSValue *r = (DSValue *)rhs;
        
        if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
            (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
            int64_t li = (l->kind == DS_VALUE_INT32) ? l->as.i32 : l->as.i64;
            int64_t ri = (r->kind == DS_VALUE_INT32) ? r->as.i32 : r->as.i64;
            return dragonstone_runtime_box_bool(li <= ri);
        }
        
        if (l->kind == DS_VALUE_FLOAT || r->kind == DS_VALUE_FLOAT) {
            double ld = dragonstone_runtime_unbox_float(lhs);
            double rd = dragonstone_runtime_unbox_float(rhs);
            return dragonstone_runtime_box_bool(ld <= rd);
        }
    }
    
    if (!ds_is_boxed(lhs) && !ds_is_boxed(rhs)) {
        return dragonstone_runtime_box_bool(strcmp((char*)lhs, (char*)rhs) <= 0);
    }
    
    return dragonstone_runtime_box_bool(false);
}

void *dragonstone_runtime_eq(void *lhs, void *rhs) {
    if (lhs == NULL && rhs == NULL) {
        return dragonstone_runtime_box_bool(true);
    }
    if (lhs == NULL || rhs == NULL) {
        return dragonstone_runtime_box_bool(false);
    }

    void *over = ds_try_invoke_operator(lhs, "==", rhs);
    if (over) return ds_is_boxed(over) && ((DSValue *)over)->kind == DS_VALUE_BOOL ? over : ds_box_truthy(over);

    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *l = (DSValue *)lhs;
        DSValue *r = (DSValue *)rhs;

        if ((l->kind == DS_VALUE_INT32 || l->kind == DS_VALUE_INT64) &&
            (r->kind == DS_VALUE_INT32 || r->kind == DS_VALUE_INT64)) {
            return dragonstone_runtime_box_bool(dragonstone_runtime_unbox_i64(lhs) == dragonstone_runtime_unbox_i64(rhs));
        }

        if (l->kind == DS_VALUE_FLOAT || r->kind == DS_VALUE_FLOAT) {
            return dragonstone_runtime_box_bool(dragonstone_runtime_unbox_float(lhs) == dragonstone_runtime_unbox_float(rhs));
        }

        if (l->kind == DS_VALUE_BOOL && r->kind == DS_VALUE_BOOL) {
            return dragonstone_runtime_box_bool(l->as.boolean == r->as.boolean);
        }

        return dragonstone_runtime_box_bool(dragonstone_runtime_case_compare(lhs, rhs));
    }

    if (!ds_is_boxed(lhs) && !ds_is_boxed(rhs)) {
        return dragonstone_runtime_box_bool(strcmp((const char *)lhs, (const char *)rhs) == 0);
    }

    return dragonstone_runtime_box_bool(false);
}

void *dragonstone_runtime_ne(void *lhs, void *rhs) {
    void *over = ds_try_invoke_operator(lhs, "!=", rhs);
    if (over) return ds_is_boxed(over) && ((DSValue *)over)->kind == DS_VALUE_BOOL ? over : ds_box_truthy(over);

    void *eq = ds_try_invoke_operator(lhs, "==", rhs);
    if (eq) {
        _Bool v = dragonstone_runtime_is_truthy(eq);
        return dragonstone_runtime_box_bool(!v);
    }

    void *fallback_eq = dragonstone_runtime_eq(lhs, rhs);
    _Bool v = dragonstone_runtime_is_truthy(fallback_eq);
    return dragonstone_runtime_box_bool(!v);
}

_Bool dragonstone_runtime_is_truthy(void *value) {
    if (!value) return false;
    if (ds_is_boxed(value)) {
        DSValue *box = (DSValue *)value;
        if (box->kind == DS_VALUE_BOOL) return box->as.boolean;
    }
    return true;
}
