/*
    * Dragonstone Garbage Collection Implementation
    * 
    * Hybrid memory management:
    *   - Area-based allocation with explicit lifecycle
    *   - Boehm GC fallback for out-of-area allocations
*/

#include "gc.h"
#include <gc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* 
    * ============================================================================
    * Internal Structures
    * ============================================================================
*/

// Single allocation tracked within an area.
typedef struct DragonstoneGcAllocation 
{
    void* ptr;
    size_t size;
    DragonstoneGcFinalizer finalizer;
    void* finalizer_userdata;
} DragonstoneGcAllocation;

// GC Area - tracks allocations for bulk free
struct DragonstoneGcArea 
{
    DragonstoneGcAllocation* allocations;
    size_t count;
    size_t capacity;
    struct DragonstoneGcArea* parent;
    char* debug_name;
    const char* opened_at_file;
    int opened_at_line;
    size_t total_bytes;
};

// Global GC Manager.
struct DragonstoneGcManager 
{
    DragonstoneGcArea* current_area;
    int disable_depth;
    bool initialized;
    bool verbose;
    size_t total_allocated;
    size_t total_freed;
    size_t area_count;
};

// Global instance.
static DragonstoneGcManager dragonstone_gc_global = 
{
    .current_area = NULL,
    .disable_depth = 0,
    .initialized = false,
    .verbose = false,
    .total_allocated = 0,
    .total_freed = 0,
    .area_count = 0
};

/* 
    * ============================================================================
    * Internal Helpers
    * ============================================================================
*/

static void dragonstone_gc_log(const char* fmt, ...) 
{
    if (!dragonstone_gc_global.verbose) return;
    
    va_list args;
    va_start(args, fmt);
    fprintf(stderr, "[Dragonstone GC] ");
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
}

static void dragonstone_gc_warn(const char* fmt, ...) 
{
    va_list args;
    va_start(args, fmt);
    fprintf(stderr, "[Dragonstone GC Warning] ");
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
}

static void dragonstone_gc_area_grow(DragonstoneGcArea* area) 
{
    size_t new_capacity = area->capacity == 0 ? 64 : area->capacity * 2;
    DragonstoneGcAllocation* new_allocs = realloc( area->allocations, new_capacity * sizeof(DragonstoneGcAllocation));
    
    if (!new_allocs) 
    {
        dragonstone_gc_warn("Failed to grow area allocation tracking");
        return;
    }
    
    area->allocations = new_allocs;
    area->capacity = new_capacity;
}

static void dragonstone_gc_area_track(DragonstoneGcArea* area, void* ptr, size_t size, DragonstoneGcFinalizer finalizer, void* userdata) 
{
    if (area->count >= area->capacity) 
    {
        dragonstone_gc_area_grow(area);
    }
    
    if (area->count < area->capacity) 
    {
        area->allocations[area->count] = (DragonstoneGcAllocation)
        {
            .ptr = ptr,
            .size = size,
            .finalizer = finalizer,
            .finalizer_userdata = userdata
        };
        area->count++;
        area->total_bytes += size;
    }
}

static bool dragonstone_gc_area_untrack(DragonstoneGcArea* area, void* ptr, size_t* out_size) 
{
    for (size_t i = 0; i < area->count; i++) 
    {
        if (area->allocations[i].ptr == ptr) 
        {
            if (out_size) {
                *out_size = area->allocations[i].size;
            }
            
            // Swap with last element and shrink.
            area->total_bytes -= area->allocations[i].size;
            area->allocations[i] = area->allocations[area->count - 1];
            area->count--;
            return true;
        }
    }
    return false;
}

static bool dragonstone_gc_area_is_ancestor(DragonstoneGcArea* ancestor, DragonstoneGcArea* descendant) 
{
    DragonstoneGcArea* current = descendant->parent;
    while (current) 
    {
        if (current == ancestor) return true;
        current = current->parent;
    }
    return false;
}

/* 
    * ============================================================================
    * Initialization
    * ============================================================================
*/

void dragonstone_gc_init(void) 
{
    if (dragonstone_gc_global.initialized) return;
    
    GC_INIT();
    
    dragonstone_gc_global.current_area = NULL;
    dragonstone_gc_global.disable_depth = 0;
    dragonstone_gc_global.initialized = true;
    dragonstone_gc_global.verbose = false;
    dragonstone_gc_global.total_allocated = 0;
    dragonstone_gc_global.total_freed = 0;
    dragonstone_gc_global.area_count = 0;
    
    dragonstone_gc_log("Initialized");
}

void dragonstone_gc_shutdown(void) 
{
    if (!dragonstone_gc_global.initialized) return;
    
    // Warn about unclosed areas.
    if (dragonstone_gc_global.current_area != NULL) 
    {
        dragonstone_gc_warn("Unclosed GC areas at shutdown. Did you forget dragonstone_gc_end_area()?");
        
        DragonstoneGcArea* area = dragonstone_gc_global.current_area;
        int depth = 0;

        while (area) 
        {
            const char* name = area->debug_name ? area->debug_name : "(unnamed)";
            dragonstone_gc_warn("  [%d] Unclosed area: %s (%zu allocations, %zu bytes)", depth, name, area->count, area->total_bytes);
            area = area->parent;
            depth++;
        }
        
        // Clean up anyway to prevent leaks.
        while (dragonstone_gc_global.current_area) 
        {
            dragonstone_gc_end_area(dragonstone_gc_global.current_area);
        }
    }
    
    // Final boehm collection.
    GC_gcollect();
    
    dragonstone_gc_log("Shutdown complete. Total allocated: %zu, freed: %zu", dragonstone_gc_global.total_allocated, dragonstone_gc_global.total_freed);
    dragonstone_gc_global.initialized = false;
}

/* 
    * ============================================================================
    * Allocation
    * ============================================================================
*/

void* dragonstone_gc_alloc(size_t size) 
{
    if (!dragonstone_gc_global.initialized) 
    {
        dragonstone_gc_init();
    }
    
    void* ptr;
    DragonstoneGcArea* area = dragonstone_gc_global.current_area;
    
    if (area) 
    {
        // Allocate in current area using malloc (freed in bulk at area end).
        ptr = malloc(size);
        if (ptr) 
        {
            dragonstone_gc_area_track(area, ptr, size, NULL, NULL);
            dragonstone_gc_global.total_allocated += size;
            dragonstone_gc_log("Area alloc: %zu bytes at %p (area: %s)", size, ptr, area->debug_name ? area->debug_name : "(unnamed)");
        }
    } 
    else 
    {
        // No active area, use boehm GC.
        ptr = GC_MALLOC(size);

        if (ptr) 
        {
            dragonstone_gc_global.total_allocated += size;
            dragonstone_gc_log("Boehm alloc: %zu bytes at %p", size, ptr);
        }
    }
    
    if (!ptr) 
    {
        // Try collection and retry.
        dragonstone_gc_collect();
        if (area) 
        {
            ptr = malloc(size);

            if (ptr) 
            {
                dragonstone_gc_area_track(area, ptr, size, NULL, NULL);
                dragonstone_gc_global.total_allocated += size;
            }
        } 
        else 
        {
            ptr = GC_MALLOC(size);
            if (ptr) 
            {
                dragonstone_gc_global.total_allocated += size;
            }
        }
    }
    
    return ptr;
}

void* dragonstone_gc_alloc_atomic(size_t size) 
{
    if (!dragonstone_gc_global.initialized) 
    {
        dragonstone_gc_init();
    }
    
    void* ptr;
    DragonstoneGcArea* area = dragonstone_gc_global.current_area;
    
    if (area) 
    {
        // Atomic hint doesn't matter for area allocations.
        ptr = malloc(size);
        if (ptr) {
            dragonstone_gc_area_track(area, ptr, size, NULL, NULL);
            dragonstone_gc_global.total_allocated += size;
        }
    } 
    else 
    {
        // Use Boehm's atomic malloc (no pointer scanning).
        ptr = GC_MALLOC_ATOMIC(size);
        if (ptr) 
        {
            dragonstone_gc_global.total_allocated += size;
        }
    }
    
    return ptr;
}

void* dragonstone_gc_alloc_with_finalizer(size_t size, DragonstoneGcFinalizer finalizer, void* userdata) 
{
    if (!dragonstone_gc_global.initialized) 
    {
        dragonstone_gc_init();
    }
    
    void* ptr;
    DragonstoneGcArea* area = dragonstone_gc_global.current_area;
    
    if (area) 
    {
        ptr = malloc(size);

        if (ptr) 
        {
            dragonstone_gc_area_track(area, ptr, size, finalizer, userdata);
            dragonstone_gc_global.total_allocated += size;
        }
    } 
    else 
    {
        ptr = GC_MALLOC(size);
        if (ptr) 
        {
            if (finalizer) 
            {
                GC_REGISTER_FINALIZER(ptr, (GC_finalization_proc)finalizer, userdata, NULL, NULL);
            }
            dragonstone_gc_global.total_allocated += size;
        }
    }
    
    return ptr;
}

void* dragonstone_gc_realloc(void* ptr, size_t size) 
{
    if (!ptr) 
    {
        return dragonstone_gc_alloc(size);
    }
    
    if (size == 0) 
    {
        // Realloc to 0 is implementation-defined; treat as no-op.
        return ptr;
    }
    
    DragonstoneGcArea* area = dragonstone_gc_find_area(ptr);
    
    if (area) 
    {
        // Find and update tracking.
        size_t old_size = 0;

        for (size_t i = 0; i < area->count; i++) 
        {
            if (area->allocations[i].ptr == ptr) 
            {
                old_size = area->allocations[i].size;
                void* new_ptr = realloc(ptr, size);
                
                if (new_ptr) 
                {
                    area->allocations[i].ptr = new_ptr;
                    area->allocations[i].size = size;
                    area->total_bytes = area->total_bytes - old_size + size;
                    dragonstone_gc_global.total_allocated += (size > old_size) ? (size - old_size) : 0;
                    return new_ptr;
                }

                return NULL;
            }
        }
        // Not found in area, shouldn't happen.
        dragonstone_gc_warn("realloc: pointer not found in expected area");
        return NULL;
    } 
    else 
    {
        // boehm-managed.
        return GC_REALLOC(ptr, size);
    }
}

void* dragonstone_gc_memdup(const void* ptr, size_t size) {
    if (!ptr || size == 0) return NULL;
    
    void* new_ptr = dragonstone_gc_alloc(size);
    if (new_ptr) {
        memcpy(new_ptr, ptr, size);
    }
    return new_ptr;
}

/* 
    * ============================================================================
    * Area Management
    * ============================================================================
*/

DragonstoneGcArea* dragonstone_gc_begin_area(void) 
{
    return dragonstone_gc_begin_area_named(NULL);
}

DragonstoneGcArea* dragonstone_gc_begin_area_named(const char* name) 
{
    if (!dragonstone_gc_global.initialized) 
    {
        dragonstone_gc_init();
    }
    
    // Area metadata lives in boehm (survives area destruction).
    DragonstoneGcArea* area = GC_MALLOC(sizeof(DragonstoneGcArea));
    if (!area) 
    {
        dragonstone_gc_warn("Failed to allocate GC area");
        return NULL;
    }
    
    area->allocations = NULL;
    area->count = 0;
    area->capacity = 0;
    area->parent = dragonstone_gc_global.current_area;
    area->debug_name = name ? strdup(name) : NULL;
    area->opened_at_file = NULL;
    area->opened_at_line = 0;
    area->total_bytes = 0;
    
    dragonstone_gc_global.current_area = area;
    dragonstone_gc_global.area_count++;
    
    dragonstone_gc_log("Begin area: %s (depth: %zu)", name ? name : "(unnamed)", dragonstone_gc_global.area_count);

    return area;
}

void dragonstone_gc_end_area(DragonstoneGcArea* area) 
{
    if (!area) 
    {
        dragonstone_gc_warn("end_area called with NULL");
        return;
    }
    
    // Check for mismatched begin/end.
    if (area != dragonstone_gc_global.current_area) 
    {
        dragonstone_gc_warn("Mismatched area end. Expected: %s, Got: %s", dragonstone_gc_global.current_area ? (dragonstone_gc_global.current_area->debug_name ? dragonstone_gc_global.current_area->debug_name : "(unnamed)") : "(none)", area->debug_name ? area->debug_name : "(unnamed)");
    }
    
    dragonstone_gc_log("End area: %s (%zu allocations, %zu bytes)", area->debug_name ? area->debug_name : "(unnamed)", area->count, area->total_bytes);
    
    // Run finalizers in reverse order.
    for (size_t i = area->count; i > 0; i--) 
    {
        DragonstoneGcAllocation* alloc = &area->allocations[i - 1];
        if (alloc->finalizer) 
        {
            alloc->finalizer(alloc->ptr, alloc->finalizer_userdata);
        }
    }
    
    // Free all allocations.
    for (size_t i = 0; i < area->count; i++) 
    {
        dragonstone_gc_global.total_freed += area->allocations[i].size;
        free(area->allocations[i].ptr);
    }
    
    // Free tracking array.
    free(area->allocations);
    
    // Free debug name.
    if (area->debug_name) 
    {
        free(area->debug_name);
    }
    
    // Pop to parent.
    dragonstone_gc_global.current_area = area->parent;
    dragonstone_gc_global.area_count--;
    
    // Area struct itself is in boehm, will be collected automatically.
}

DragonstoneGcArea* dragonstone_gc_current_area(void) 
{
    return dragonstone_gc_global.current_area;
}

DragonstoneGcArea* dragonstone_gc_area_parent(DragonstoneGcArea* area) 
{
    return area ? area->parent : NULL;
}

const char* dragonstone_gc_area_name(DragonstoneGcArea* area) 
{
    return area ? area->debug_name : NULL;
}

size_t dragonstone_gc_area_count(DragonstoneGcArea* area) 
{
    return area ? area->count : 0;
}

/* 
    * ============================================================================
    * Escape / Promotion
    * ============================================================================
*/

void* dragonstone_gc_escape(void* ptr) 
{
    if (!ptr) return NULL;
    
    DragonstoneGcArea* current = dragonstone_gc_global.current_area;
    if (!current) 
    {
        // Already in Boehm.
        return ptr;
    }
    
    return dragonstone_gc_escape_to(ptr, current->parent);
}

void* dragonstone_gc_escape_to(void* ptr, DragonstoneGcArea* target_area) 
{
    if (!ptr) return NULL;
    
    // Find which area this pointer is in.
    DragonstoneGcArea* source_area = dragonstone_gc_find_area(ptr);
    
    if (!source_area) 
    {
        // Already in Boehm, nothing to do.
        return ptr;
    }
    
    if (source_area == target_area) 
    {
        // Already in target area.
        return ptr;
    }
    
    // Untrack from source area.
    size_t size = 0;
    DragonstoneGcFinalizer finalizer = NULL;

    void* finalizer_userdata = NULL;
    
    for (size_t i = 0; i < source_area->count; i++) 
    {
        if (source_area->allocations[i].ptr == ptr) 
        {
            size = source_area->allocations[i].size;
            finalizer = source_area->allocations[i].finalizer;
            finalizer_userdata = source_area->allocations[i].finalizer_userdata;
            
            // Remove from source.
            source_area->total_bytes -= size;
            source_area->allocations[i] = source_area->allocations[source_area->count - 1];
            source_area->count--;
            break;
        }
    }
    
    if (size == 0) 
    {
        dragonstone_gc_warn("escape: pointer not found in any area");
        return ptr;
    }
    
    if (target_area) 
    {
        // Move to target area.
        dragonstone_gc_area_track(target_area, ptr, size, finalizer, finalizer_userdata);
        dragonstone_gc_log("Escaped %p (%zu bytes) to area: %s", ptr, size, target_area->debug_name ? target_area->debug_name : "(unnamed)");
        return ptr;
    } 
    else 
    {

        // Promote to boehm; need to copy since original is malloc.
        void* new_ptr = GC_MALLOC(size);
        if (new_ptr) 
        {
            memcpy(new_ptr, ptr, size);
            if (finalizer) 
            {
                GC_REGISTER_FINALIZER(new_ptr, (GC_finalization_proc)finalizer, 
                                      finalizer_userdata, NULL, NULL);
            }
            // Free the malloc original.
            free(ptr);
            dragonstone_gc_log("Escaped %p -> %p (%zu bytes) to Boehm", ptr, new_ptr, size);
            return new_ptr;
        } 
        else 
        {
            dragonstone_gc_warn("Failed to allocate during escape to Boehm");
            // retrack in source to prevent leak.
            dragonstone_gc_area_track(source_area, ptr, size, finalizer, finalizer_userdata);
            return ptr;
        }
    }
}

void* dragonstone_gc_copy(const void* ptr, size_t size) 
{
    return dragonstone_gc_memdup(ptr, size);
}

/* 
    * ============================================================================
    * Enable / Disable
    * ============================================================================
*/

void dragonstone_gc_disable(void) 
{
    if (dragonstone_gc_global.disable_depth == 0) 
    {
        GC_disable();
    }
    dragonstone_gc_global.disable_depth++;
    dragonstone_gc_log("Disabled (depth: %d)", dragonstone_gc_global.disable_depth);
}

void dragonstone_gc_enable(void) 
{
    if (dragonstone_gc_global.disable_depth > 0) 
    {
        dragonstone_gc_global.disable_depth--;
        if (dragonstone_gc_global.disable_depth == 0) 
        {
            GC_enable();
        }
        dragonstone_gc_log("Enabled (depth: %d)", dragonstone_gc_global.disable_depth);
    } 
    else 
    {
        dragonstone_gc_warn("enable called without matching disable");
    }
}

bool dragonstone_gc_is_enabled(void) 
{
    return dragonstone_gc_global.disable_depth == 0;
}

int dragonstone_gc_disable_depth(void) 
{
    return dragonstone_gc_global.disable_depth;
}

/* 
    * ============================================================================
    * Collection
    * ============================================================================
*/

void dragonstone_gc_collect(void) 
{
    if (dragonstone_gc_global.disable_depth == 0) 
    {
        dragonstone_gc_log("Forcing collection");
        GC_gcollect();
    } else {
        dragonstone_gc_log("Collection requested but GC is disabled");
    }
}

void dragonstone_gc_collect_if_needed(void) 
{
    if (dragonstone_gc_global.disable_depth == 0) 
    {
        GC_collect_a_little();
    }
}

/* 
    * ============================================================================
    * Write Barrier
    * ============================================================================
*/

void dragonstone_gc_write_barrier(void* container, void* value) 
{
    if (!container || !value) return;
    
    DragonstoneGcArea* container_area = dragonstone_gc_find_area(container);
    DragonstoneGcArea* value_area = dragonstone_gc_find_area(value);
    
    // Check for dangerous cross-area reference.
    if (value_area && container_area != value_area) 
    {
        // Value is in a nested area that might be cleared before container.
        if (!container_area || dragonstone_gc_area_is_ancestor(container_area, value_area)) 
        {
            dragonstone_gc_warn(
                "Cross-area reference detected: container in %s references value in %s. "
                "The value may be freed while container still references it. "
                "Consider using dragonstone_gc_escape().",
                container_area ? (container_area->debug_name ? container_area->debug_name : "(unnamed)") : "Boehm",
                value_area->debug_name ? value_area->debug_name : "(unnamed)"
            );
        }
    }
}

bool dragonstone_gc_is_in_area(void* ptr, DragonstoneGcArea* area) 
{
    if (!ptr) return false;
    
    if (!area) 
    {
        // Check if NOT in any area (ex: in boehm).
        return dragonstone_gc_find_area(ptr) == NULL;
    }
    
    for (size_t i = 0; i < area->count; i++) 
    {
        if (area->allocations[i].ptr == ptr) 
        {
            return true;
        }
    }
    return false;
}

DragonstoneGcArea* dragonstone_gc_find_area(void* ptr) {
    if (!ptr) return NULL;
    
    // Search from current area up through parents.
    DragonstoneGcArea* area = dragonstone_gc_global.current_area;
    while (area) 
    {
        for (size_t i = 0; i < area->count; i++) 
        {
            if (area->allocations[i].ptr == ptr) 
            {
                return area;
            }
        }
        area = area->parent;
    }
    
    // Not in any area, must be boehm-managed.
    return NULL;
}

/* 
    * ============================================================================
    * Statistics & Debugging
    * ============================================================================
*/

DragonstoneGcStats dragonstone_gc_get_stats(void) {
    DragonstoneGcStats stats = 
    {
        .total_allocated = dragonstone_gc_global.total_allocated,
        .total_freed = dragonstone_gc_global.total_freed,
        .current_area_depth = dragonstone_gc_global.area_count,
        .current_area_allocations = dragonstone_gc_global.current_area ? dragonstone_gc_global.current_area->count : 0,
        .boehm_heap_size = GC_get_heap_size(),
        .area_count = dragonstone_gc_global.area_count,
        .disable_depth = dragonstone_gc_global.disable_depth
    };
    return stats;
}

void dragonstone_gc_set_verbose(bool enabled) 
{
    dragonstone_gc_global.verbose = enabled;
}

bool dragonstone_gc_is_verbose(void) 
{
    return dragonstone_gc_global.verbose;
}

void dragonstone_gc_dump_state(void) 
{
    DragonstoneGcStats stats = dragonstone_gc_get_stats();
    
    fprintf(stderr, "--- Dragonstone Garbage Collection States ---\n");
    fprintf(stderr, "Initialized:      %s\n", dragonstone_gc_global.initialized ? "yes" : "no");
    fprintf(stderr, "Total allocated:  %zu bytes\n", stats.total_allocated);
    fprintf(stderr, "Total freed:      %zu bytes\n", stats.total_freed);
    fprintf(stderr, "Net allocated:    %zu bytes\n", stats.total_allocated - stats.total_freed);
    fprintf(stderr, "Boehm heap size:  %zu bytes\n", stats.boehm_heap_size);
    fprintf(stderr, "Area depth:       %zu\n", stats.current_area_depth);
    fprintf(stderr, "Disable depth:    %d\n", stats.disable_depth);
    fprintf(stderr, "Verbose:          %s\n", dragonstone_gc_global.verbose ? "yes" : "no");
    fprintf(stderr, "-------------------------------------------\n");
}

void dragonstone_gc_dump_areas(void) {
    fprintf(stderr, "--- Dragonstone Garbage Collection Areas ----\n");
    
    if (!dragonstone_gc_global.current_area) 
    {
        fprintf(stderr, "(no active areas)\n");
        fprintf(stderr, "---------------------------------------------\n");
        return;
    }
    
    DragonstoneGcArea* area = dragonstone_gc_global.current_area;
    int depth = 0;
    
    while (area) 
    {
        const char* name = area->debug_name ? area->debug_name : "(unnamed)";
        fprintf(stderr, "[%d] %s\n", depth, name);
        fprintf(stderr, "    Allocations: %zu\n", area->count);
        fprintf(stderr, "    Total bytes: %zu\n", area->total_bytes);
        fprintf(stderr, "    Capacity:    %zu\n", area->capacity);
        
        area = area->parent;
        depth++;
    }
    
    fprintf(stderr, "---------------------------------------------\n");
}

/* 
    * ============================================================================
    * Memory Mode Helpers
    * ============================================================================
*/

DragonstoneMemoryMode dragonstone_memory_mode_default(void)
{
    return (DragonstoneMemoryMode)
    {
        .gc = DRAGONSTONE_GC_MODE_ENABLED,
        .ownership = DRAGONSTONE_OWNERSHIP_MODE_ENABLED,
        .area_name = NULL,
        .escape_return = false
    };
}

DragonstoneMemoryMode dragonstone_memory_mode_create(
    DragonstoneGcMode gc,
    DragonstoneOwnershipMode ownership,
    const char* area_name,
    bool escape_ret
)
{
    return (DragonstoneMemoryMode)
    {
        .gc = gc,
        .ownership = ownership,
        .area_name = area_name,
        .escape_return = escape_ret
    };
}

bool dragonstone_memory_mode_gc_enabled(DragonstoneMemoryMode mode)
{
    return (mode.gc & DRAGONSTONE_GC_MODE_ENABLED) != 0 || (mode.gc & DRAGONSTONE_GC_MODE_AREA) != 0;
}

bool dragonstone_memory_mode_ownership_enabled(DragonstoneMemoryMode mode)
{
    return (mode.ownership & DRAGONSTONE_OWNERSHIP_MODE_ENABLED) != 0;
}

bool dragonstone_memory_mode_uses_area(DragonstoneMemoryMode mode)
{
    return (mode.gc & DRAGONSTONE_GC_MODE_AREA) != 0;
}
