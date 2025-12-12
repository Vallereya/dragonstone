#define _CRT_SECURE_NO_WARNINGS
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <ctype.h>
#include <setjmp.h>

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

typedef struct DSMethod {
    char *name;
    void *func_ptr;
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
void *dragonstone_runtime_to_string(void *value);
void *dragonstone_runtime_tuple_literal(int64_t l, void **e);
void *dragonstone_runtime_named_tuple_literal(int64_t l, void **k, void **v);

void *dragonstone_runtime_gt(void *lhs, void *rhs);
void *dragonstone_runtime_lt(void *lhs, void *rhs);
void *dragonstone_runtime_gte(void *lhs, void *rhs);
void *dragonstone_runtime_lte(void *lhs, void *rhs);
void *dragonstone_runtime_eq(void *lhs, void *rhs);
void *dragonstone_runtime_ne(void *lhs, void *rhs);

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
        DSMapEntry *entry = (DSMapEntry *)ds_alloc(sizeof(DSMapEntry));
        entry->key = keys[i];
        entry->value = values[i];
        
        entry->next = map->head;
        map->head = entry;
        map->count++;
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
                    strcat(buffer, ": ");
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

void *dragonstone_runtime_block_literal(void *f, void *e) {
    DSBlock *blk = (DSBlock *)ds_alloc(sizeof(DSBlock));
    blk->func = (BlockFunc)f;
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

static void *ds_call_method(void *func_ptr, void *receiver, int64_t argc, void **argv) {
    if (argc == 0) return ((Method0)func_ptr)(receiver);
    if (argc == 1) return ((Method1)func_ptr)(receiver, argv[0]);
    if (argc == 2) return ((Method2)func_ptr)(receiver, argv[0], argv[1]);
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

    snode = singleton_methods;
    while (snode) {
        if (strcmp(snode->name, method) == 0) {
            return ds_call_method(snode->func_ptr, receiver, argc, argv);
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

            DSMethod *meth = cls->methods;
            while (meth) {
                if (strcmp(meth->name, "initialize") == 0) {
                    ds_call_method(meth->func_ptr, inst_box, argc, argv);
                    break;
                }
                meth = meth->next;
            }
            
            return inst_box;
        }
        DSMethod *meth = cls->methods;
        while (meth) {
            if (strcmp(meth->name, method) == 0) {
                return ds_call_method(meth->func_ptr, receiver, argc, argv);
            }
            meth = meth->next;
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
        DSMethod *curr = cls->methods;
        while (curr) {
            if (strcmp(curr->name, method) == 0) {
                return ds_call_method(curr->func_ptr, receiver, argc, argv);
            }
            curr = curr->next;
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
                    DSMapEntry *entry = (DSMapEntry *)ds_alloc(sizeof(DSMapEntry));
                    entry->key = curr->key;
                    entry->value = curr->value;
                    entry->next = out->head;
                    out->head = entry;
                    out->count++;
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
    mod->next = global_classes;
    mod->is_module = true;
    global_classes = mod;
    
    DSValue *box = ds_new_box(DS_VALUE_CLASS);
    box->as.ptr = mod;
    mod->cached_box = box;
    
    ds_constant_set(&global_constants, name, box);
    return box;
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
}

void dragonstone_runtime_define_method(void *class_box_ptr, void *name_ptr, void *func_ptr) {
    if (!ds_is_boxed(class_box_ptr)) return;
    DSValue *box = (DSValue *)class_box_ptr;
    if (box->kind != DS_VALUE_CLASS) return;
    DSClass *cls = (DSClass *)box->as.ptr;
    const char *method_name = (const char *)name_ptr;
    DSMethod *m = (DSMethod *)ds_alloc(sizeof(DSMethod));
    m->name = ds_strdup(method_name);
    m->func_ptr = func_ptr;
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

    return NULL; 
}

void *dragonstone_runtime_value_display(void *value) { return ds_format_value(value, true); }
void *dragonstone_runtime_to_string(void *value) { return ds_value_to_string(value); }

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

    DSMapEntry *curr = inst->ivars->head;
    while (curr) {
        if (strcmp((char *)curr->key, (char *)name) == 0) return curr->value;
        curr = curr->next;
    }
    return NULL;
}

void *dragonstone_runtime_ivar_set(void *obj, void *name, void *val) {
    if (!ds_is_boxed(obj)) return val;
    DSValue *box = (DSValue *)obj;
    if (box->kind != DS_VALUE_INSTANCE) return val;
    DSInstance *inst = (DSInstance *)box->as.ptr;

    if (!inst->ivars) {
        inst->ivars = (DSMap *)ds_alloc(sizeof(DSMap));
        inst->ivars->head = NULL;
        inst->ivars->count = 0;
    }

    DSMapEntry *curr = inst->ivars->head;
    while (curr) {
        if (strcmp((char *)curr->key, (char *)name) == 0) {
            curr->value = val;
            return val;
        }
        curr = curr->next;
    }

    DSMapEntry *entry = (DSMapEntry *)ds_alloc(sizeof(DSMapEntry));
    entry->key = ds_strdup((char *)name);
    entry->value = val;
    entry->next = inst->ivars->head;
    inst->ivars->head = entry;
    inst->ivars->count++;
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
        DSMapEntry *entry = (DSMapEntry *)ds_alloc(sizeof(DSMapEntry));
        entry->key = index_value;
        entry->value = value;
        entry->next = map->head;
        map->head = entry;
        map->count++;
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

    if (lhs_boxed && rhs_boxed) {
        DSValue *l = (DSValue *)lhs;
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

void **dragonstone_runtime_block_env_allocate(int64_t l) { return calloc(l, sizeof(void*)); }
void dragonstone_runtime_rescue_placeholder(void) { abort(); }
void *dragonstone_runtime_define_constant(void *n, void *v) {
    const char *name = (const char *)n;
    ds_constant_set(&global_constants, name, v);
    return v;
}
void dragonstone_runtime_yield_missing_block(void) { abort(); }
void dragonstone_runtime_extend_container(void *c, void *t) { dragonstone_runtime_extend(c, t); }

void *dragonstone_runtime_gt(void *lhs, void *rhs) {
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
    return dragonstone_runtime_box_bool(dragonstone_runtime_case_compare(lhs, rhs));
}

void *dragonstone_runtime_ne(void *lhs, void *rhs) {
    return dragonstone_runtime_box_bool(!dragonstone_runtime_case_compare(lhs, rhs));
}

_Bool dragonstone_runtime_is_truthy(void *value) {
    if (!value) return false;
    if (ds_is_boxed(value)) {
        DSValue *box = (DSValue *)value;
        if (box->kind == DS_VALUE_BOOL) return box->as.boolean;
    }
    return true;
}
