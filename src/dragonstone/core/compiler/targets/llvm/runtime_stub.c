#define _CRT_SECURE_NO_WARNINGS
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <ctype.h>

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
    DS_VALUE_RANGE
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

typedef struct DSClass {
    char *name;
    DSMethod *methods;
    struct DSClass *next;
} DSClass;

typedef struct {
    DSClass *klass;
} DSInstance;

typedef struct {
    int64_t from;
    int64_t to;
    bool exclusive;
} DSRange;

static DSClass *global_classes = NULL;

static const char DS_STR_NIL_VAL[] = "nil";
static const char DS_STR_TRUE_VAL[] = "true";
static const char DS_STR_FALSE_VAL[] = "false";

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

_Bool dragonstone_runtime_case_compare(void *lhs, void *rhs);
void *dragonstone_runtime_array_literal(int64_t length, void **elements);
void *dragonstone_runtime_value_display(void *value);
void *dragonstone_runtime_box_i64(int64_t v);
void *dragonstone_runtime_box_bool(int32_t v);
void *dragonstone_runtime_array_push(void *array_val, void *value);
void *dragonstone_runtime_block_invoke(void *block_val, int64_t argc, void **argv);

void dragonstone_runtime_raise(void *message_ptr) {
    const char *msg = (const char *)message_ptr;
    fprintf(stderr, "Runtime Error: %s\n", msg ? msg : "Unknown error");
    abort();
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

int32_t dragonstone_runtime_unbox_i32(void *v) { if(ds_is_boxed(v) && ((DSValue*)v)->kind == DS_VALUE_INT32) return ((DSValue*)v)->as.i32; return 0; }
int64_t dragonstone_runtime_unbox_i64(void *v) {
    if (!ds_is_boxed(v)) return 0;
    DSValue *box = (DSValue *)v;
    if (box->kind == DS_VALUE_INT64) return box->as.i64;
    if (box->kind == DS_VALUE_INT32) return (int64_t)box->as.i32;
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

void *dragonstone_runtime_method_invoke(void *receiver, void *method_name_ptr, int64_t argc, void **argv, void *block_val) {
    const char *method = (const char *)method_name_ptr;

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

        return NULL; 
    }

    DSValue *box = (DSValue *)receiver;

    if (box->kind == DS_VALUE_CLASS) {
        DSClass *cls = (DSClass *)box->as.ptr;
        if (strcmp(method, "new") == 0) {
            DSInstance *inst = (DSInstance *)ds_alloc(sizeof(DSInstance));
            inst->klass = cls;
            DSValue *inst_box = ds_new_box(DS_VALUE_INSTANCE);
            inst_box->as.ptr = inst;
            return inst_box;
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
    }

    if (box->kind == DS_VALUE_MAP) {
        DSMap *map = (DSMap *)box->as.ptr;
        if (strcmp(method, "length") == 0 || strcmp(method, "size") == 0) return (void *)dragonstone_runtime_box_i64(map->count);
        if (strcmp(method, "empty") == 0 || strcmp(method, "empty?") == 0) return (void *)dragonstone_runtime_box_bool(map->count == 0);
        
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
    }

    if (box->kind == DS_VALUE_RANGE) {
        DSRange *rng = (DSRange *)box->as.ptr;
        if (strcmp(method, "each") == 0) {
            if (!block_val) return receiver;
            int64_t current = rng->from;
            int64_t end = rng->to;
            void *args[1];

            if (current <= end) {
                while (current < end || (!rng->exclusive && current == end)) {
                    args[0] = dragonstone_runtime_box_i64(current);
                    dragonstone_runtime_block_invoke(block_val, 1, args);
                    current++;
                }
            }
            return receiver;
        }
        if (strcmp(method, "to_a") == 0) {
            return NULL;
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
            DSValue *box = ds_new_box(DS_VALUE_CLASS);
            box->as.ptr = curr;
            return box;
        }
        curr = curr->next;
    }
    DSClass *cls = (DSClass *)ds_alloc(sizeof(DSClass));
    cls->name = ds_strdup(name);
    cls->methods = NULL;
    cls->next = global_classes;
    global_classes = cls;
    DSValue *box = ds_new_box(DS_VALUE_CLASS);
    box->as.ptr = cls;
    return box;
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
}

void *dragonstone_runtime_constant_lookup(int64_t length, void **segments) {
    if (length == 0) return NULL;
    const char *name = (const char *)segments[0];
    DSClass *curr = global_classes;
    while (curr) {
        if (strcmp(curr->name, name) == 0) {
            DSValue *box = ds_new_box(DS_VALUE_CLASS);
            box->as.ptr = curr;
            return box;
        }
        curr = curr->next;
    }
    return NULL; 
}

void *dragonstone_runtime_value_display(void *value) { return ds_format_value(value, true); }
void *dragonstone_runtime_to_string(void *value) { return ds_value_to_string(value); }

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
        return strcmp((const char*)lhs, (const char*)rhs) == 0;
    }
    return false;
}

void *dragonstone_runtime_array_literal(int64_t length, void **elements) { return ds_create_array_box(length, elements); }
void *dragonstone_runtime_map_literal(int64_t length, void **keys, void **values) { return ds_create_map_box(length, keys, values); }

void *dragonstone_runtime_range_literal(int64_t from, int64_t to, bool exclusive) {
    DSRange *rng = (DSRange *)ds_alloc(sizeof(DSRange));
    rng->from = from;
    rng->to = to;
    rng->exclusive = exclusive;
    DSValue *box = ds_new_box(DS_VALUE_RANGE);
    box->as.ptr = rng;
    return box;
}

void *dragonstone_runtime_index_get(void *object, void *index_value) {
    if (!ds_is_boxed(object)) return NULL;
    DSValue *obj_box = (DSValue *)object;

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

void *dragonstone_runtime_tuple_literal(int64_t l, void **e) { return NULL; }
void *dragonstone_runtime_named_tuple_literal(int64_t l, void **k, void **v) { return NULL; }
void **dragonstone_runtime_block_env_allocate(int64_t l) { return calloc(l, sizeof(void*)); }
void dragonstone_runtime_rescue_placeholder(void) { abort(); }
void *dragonstone_runtime_define_constant(void *n, void *v) { return v; }
void dragonstone_runtime_yield_missing_block(void) { abort(); }
