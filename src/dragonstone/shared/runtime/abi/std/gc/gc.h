/*
    * Dragonstone Garbage Collection
    * 
    * Hybrid memory management system:
    *   - Area-based allocation for explicit lifecycle control
    *   - Boehm GC fallback for out-of-area allocations
    * 
    * Default behavior (no annotation):
    *   @[Garbage(enable) && Ownership(enable)]
    * 
    * Annotations:
    *   @[Garbage(enable)]                          - Enable GC for scope
    *   @[Garbage(disable)]                         - Disable GC for scope
    *   @[Garbage(area)]                            - Create area for scope
    *   @[Garbage(area: "name")]                    - Named area for debugging
    *   @[Garbage(area, escape: return)]            - Area with return value escape
    *   @[Garbage(enable) && Ownership(enable)]     - Both systems active
    *   @[Garbage(disable) && Ownership(enable)]    - Ownership only (zero-cost)
    *   @[Garbage(enable) || Ownership(enable)]     - Ownership preferred, GC fallback
*/

#ifndef DRAGONSTONE_GC_H
#define DRAGONSTONE_GC_H

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 
    * ============================================================================
    * Types
    * ============================================================================
*/

typedef struct DragonstoneGcArea DragonstoneGcArea;
typedef struct DragonstoneGcManager DragonstoneGcManager;
typedef void (*DragonstoneGcFinalizer)(void* ptr, void* userdata);

// Memory management mode flags.
typedef enum
{
    DRAGONSTONE_GC_MODE_DISABLED   = 0,
    DRAGONSTONE_GC_MODE_ENABLED    = 1 << 0,
    DRAGONSTONE_GC_MODE_AREA       = 1 << 1,
} DragonstoneGcMode;

typedef enum 
{
    DRAGONSTONE_OWNERSHIP_MODE_DISABLED = 0,
    DRAGONSTONE_OWNERSHIP_MODE_ENABLED  = 1 << 0,
} DragonstoneOwnershipMode;

// Combined memory mode for annotation processing.
typedef struct 
{
    DragonstoneGcMode gc;
    DragonstoneOwnershipMode ownership;
    const char* area_name;
    bool escape_return;
} DragonstoneMemoryMode;

/* 
    * ============================================================================
    * Initialization
    * ============================================================================
*/

/*
    * Initialize the GC system. Call once at program startup.
    * Initializes Boehm GC and internal structures.
*/
void dragonstone_gc_init(void);

/*
    * Shutdown the GC system. Call at program exit.
    * Reports warnings for unclosed areas and performs final cleanup.
*/
void dragonstone_gc_shutdown(void);

/* 
    * ============================================================================
    * Allocation
    * ============================================================================
*/

/*
    * Allocate managed memory.
    * Routes to current area if one is active, otherwise uses Boehm GC.
    * 
    * @param size  Number of bytes to allocate
    * @return      Pointer to allocated memory, or NULL on failure
*/
void* dragonstone_gc_alloc(size_t size);

/*
    * Allocate memory with no internal pointers (optimization hint).
    * Tells the GC this memory contains no pointers to scan.
    * 
    * @param size  Number of bytes to allocate
    * @return      Pointer to allocated memory, or NULL on failure
*/
void* dragonstone_gc_alloc_atomic(size_t size);

/*
    * Allocate memory with a finalizer callback.
    * Finalizer is called when the memory is about to be freed.
    * 
    * @param size       Number of bytes to allocate
    * @param finalizer  Callback function, or NULL for none
    * @param userdata   User data passed to finalizer
    * @return           Pointer to allocated memory, or NULL on failure
*/
void* dragonstone_gc_alloc_with_finalizer(
    size_t size,
    DragonstoneGcFinalizer finalizer,
    void* userdata
);

/*
    * Reallocate memory to a new size.
    * 
    * @param ptr   Pointer to existing allocation, or NULL for new allocation
    * @param size  New size in bytes
    * @return      Pointer to reallocated memory, or NULL on failure
*/
void* dragonstone_gc_realloc(void* ptr, size_t size);

/*
    * Duplicate memory.
    * 
    * @param ptr   Pointer to source memory
    * @param size  Number of bytes to copy
    * @return      Pointer to new allocation containing copied data
*/
void* dragonstone_gc_memdup(const void* ptr, size_t size);

/* 
    * ============================================================================
    * Area Management
    * ============================================================================
*/

/*
    * Begin a new GC area.
    * All allocations until dragonstone_gc_end_area() are tracked together
    * and freed as a unit.
    * 
    * @return  Handle to the new area
*/
DragonstoneGcArea* dragonstone_gc_begin_area(void);

/*
    * Begin a named GC area for debugging.
    * 
    * @param name  Debug name for the area (copied internally)
    * @return      Handle to the new area
*/
DragonstoneGcArea* dragonstone_gc_begin_area_named(const char* name);

/*
    * End a GC area, freeing all allocations within it.
    * Runs finalizers in reverse allocation order.
    * Warns if area != current area (mismatched begin/end).
    * 
    * @param area  Handle from dragonstone_gc_begin_area()
*/
void dragonstone_gc_end_area(DragonstoneGcArea* area);

/*
    * Get the current active area.
    * 
    * @return  Current area, or NULL if no area is active
*/
DragonstoneGcArea* dragonstone_gc_current_area(void);

/*
    * Get the parent of an area.
    * 
    * @param area  The area to query
    * @return      Parent area, or NULL if this is a root area
*/
DragonstoneGcArea* dragonstone_gc_area_parent(DragonstoneGcArea* area);

/*
    * Get the debug name of an area.
    * 
    * @param area  The area to query
    * @return      Debug name, or NULL if unnamed
*/
const char* dragonstone_gc_area_name(DragonstoneGcArea* area);

/*
    * Get the allocation count in an area.
    * 
    * @param area  The area to query
    * @return      Number of allocations in this area
*/
size_t dragonstone_gc_area_count(DragonstoneGcArea* area);

/* 
    * ============================================================================
    * Escape / Promotion
    * ============================================================================
*/

/*
    * Escape a pointer from current area to parent.
    * If no parent exists, promotes to Boehm GC.
    * 
    * @param ptr  Pointer to escape
    * @return     The (possibly new) pointer after escape
*/
void* dragonstone_gc_escape(void* ptr);

/*
    * Escape a pointer to a specific ancestor area.
    * 
    * @param ptr          Pointer to escape
    * @param target_area  Destination area, or NULL for Boehm
    * @return             The (possibly new) pointer after escape
*/
void* dragonstone_gc_escape_to(void* ptr, DragonstoneGcArea* target_area);

/*
    * Deep copy a value, allocating in current context.
    * 
    * @param ptr   Pointer to source data
    * @param size  Size of data to copy
    * @return      Pointer to new copy
*/
void* dragonstone_gc_copy(const void* ptr, size_t size);

/* 
    * ============================================================================
    * Enable / Disable
    * ============================================================================
*/

/*
    * Disable GC collection temporarily (nestable).
    * Allocations still work, but collection is deferred.
*/
void dragonstone_gc_disable(void);

/*
    * Re-enable GC collection.
    * Must be called once for each dragonstone_gc_disable().
*/
void dragonstone_gc_enable(void);

/*
    * Check if GC collection is currently enabled.
    * 
    * @return  true if enabled, false if disabled
*/
bool dragonstone_gc_is_enabled(void);

/*
    * Get the current disable depth.
    * 
    * @return  Number of nested disable calls
*/
int dragonstone_gc_disable_depth(void);

/* 
    * ============================================================================
    * Collection
    * ============================================================================
*/

/*
    * Force a collection cycle.
    * Only affects Boehm-managed memory; areas are unaffected.
*/
void dragonstone_gc_collect(void);

/*
    * Suggest a collection if memory pressure is high.
    * May be a no-op if pressure is low.
*/
void dragonstone_gc_collect_if_needed(void);

/* 
    * ============================================================================
    * Write Barrier (Cross-Area Safety)
    * ============================================================================
*/

/*
    * Write barrier for storing references.
    * Call when storing a pointer in a container.
    * Warns if storing a reference to a nested area (dangling pointer risk).
    * 
    * @param container  The object receiving the reference
    * @param value      The pointer being stored
*/
void dragonstone_gc_write_barrier(void* container, void* value);

/*
    * Check if a pointer is in a specific area.
    * 
    * @param ptr   Pointer to check
    * @param area  Area to check against, or NULL for Boehm
    * @return      true if ptr was allocated in area
*/
bool dragonstone_gc_is_in_area(void* ptr, DragonstoneGcArea* area);

/*
    * Find which area a pointer belongs to.
    * 
    * @param ptr  Pointer to look up
    * @return     Area containing ptr, or NULL if Boehm-managed
*/
DragonstoneGcArea* dragonstone_gc_find_area(void* ptr);

/* 
    * ============================================================================
    * Statistics & Debugging
    * ============================================================================
*/

typedef struct {
    size_t total_allocated;             // Total bytes allocated.
    size_t total_freed;                 // Total bytes freed.
    size_t current_area_depth;          // Nesting depth of areas.
    size_t current_area_allocations;    // Allocations in current area.
    size_t boehm_heap_size;             // Boehm GC heap size.
    size_t area_count;                  // Number of active areas.
    int    disable_depth;               // GC disable nesting depth.
} DragonstoneGcStats;

/*
    * Get current GC statistics.
    * 
    * @return  Statistics structure
*/
DragonstoneGcStats dragonstone_gc_get_stats(void);

/*
    * Enable verbose GC logging.
    * Logs area creation/destruction, allocations, warnings.
    * 
    * @param enabled  true to enable, false to disable
*/
void dragonstone_gc_set_verbose(bool enabled);

/*
    * Check if verbose logging is enabled.
    * 
    * @return  true if verbose logging is on
*/
bool dragonstone_gc_is_verbose(void);

/*
    * Dump current GC state to stderr.
    * Useful for debugging memory issues.
*/
void dragonstone_gc_dump_state(void);

/*
    * Dump area hierarchy to stderr.
*/
void dragonstone_gc_dump_areas(void);

/* 
    * ============================================================================
    * Memory Mode Helpers
    * ============================================================================
*/

/*
    * Create default memory mode (both GC and Ownership enabled).
    * 
    * @return  Default memory mode
*/
DragonstoneMemoryMode dragonstone_memory_mode_default(void);

/*
    * Create memory mode from annotation flags.
    * 
    * @param gc          GC mode flags
    * @param ownership   Ownership mode flags
    * @param area_name   Area name, or NULL
    * @param escape_ret  Whether return values escape
    * @return            Combined memory mode
*/
DragonstoneMemoryMode dragonstone_memory_mode_create(
    DragonstoneGcMode gc,
    DragonstoneOwnershipMode ownership,
    const char* area_name,
    bool escape_ret
);

/*
    * Check if GC is enabled in a memory mode.
*/
bool dragonstone_memory_mode_gc_enabled(DragonstoneMemoryMode mode);

/*
    * Check if ownership is enabled in a memory mode.
*/
bool dragonstone_memory_mode_ownership_enabled(DragonstoneMemoryMode mode);

/*
    * Check if mode uses areas.
*/
bool dragonstone_memory_mode_uses_area(DragonstoneMemoryMode mode);

#ifdef __cplusplus
}
#endif

#endif
