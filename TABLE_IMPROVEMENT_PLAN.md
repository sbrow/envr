# Table Rendering Memory Optimization Plan

## Executive Summary

This plan outlines improvements to eliminate excessive memory allocations and copies in the Odin table rendering system. The current implementation makes 10+ allocations per row, while the Zig equivalent makes zero allocations for rendering. This optimization will reduce memory usage, improve performance, and align with the project's efficiency goals.

## Current State Analysis

### Zig Version (Reference Implementation)
- **Allocations**: 1 (data only)
- **Data copies**: 0
- **String allocation**: 0
- **Column widths**: Stack array
- **Output**: Direct to writer

### Odin Version (Current Implementation)
- **Allocations**: 10+ per row
- **Data copies**: Multiple per row
- **String allocation**: 2+ per row (concatenate + slice)
- **Column widths**: Heap allocated
- **Output**: Builder → stdout

### Current Issues Identified

1. **Table Infrastructure** (`table.odin`)
   - Uses `strings.Builder` which allocates per-line memory
   - Heap-allocated `[dynamic]int` for column widths
   - Multiple `strings.concatenate()` calls creating new strings

2. **Command Implementations**
   - `cmd_list`: Creates intermediate `[]string` slices per row, allocates new strings via `strings.concatenate()`
   - `cmd_sync`: Creates `SyncEntry` structs with cloned strings, allocates dynamic arrays
   - `cmd_deps`: Allocates dynamic rows array unnecessarily

3. **Memory Pattern**
   - Each command allocates `[][]string` for table data
   - Manual struct-to-row transformation creates copies
   - Duplicate code across all table-using commands

## Proposed Solutions

### Phase 1: Core Table Infrastructure Overhaul

#### 1.1 Direct Writer-Based Rendering
**Current:**
```odin
b: strings.Builder
strings.builder_init(&b)
// ... build table in builder
fmt.println(strings.to_string(b))
```

**Proposed:**
```odin
render_table :: proc(writer: io.Writer, headers: []string, rows: [][]string)
```
- Replace `strings.Builder` with `io.Writer` output
- Eliminate intermediate string allocations
- Write table components directly to output stream

#### 1.2 Stack-Based Column Widths
**Current:**
```odin
col_widths := make([dynamic]int, 0, len(headers))
```

**Proposed:**
- Use fixed stack arrays for reasonable column counts
- Implement small buffer optimization (SBO) for variable column counts
- Only allocate for tables exceeding threshold (e.g., 16 columns)

#### 1.3 Zero-Copy String Handling
**Current:**
```odin
dir_str := strings.concatenate({row.Dir, "/"}, context.temp_allocator)
```

**Proposed:**
- Replace `strings.concatenate()` with string slicing
- Work directly with `EnvFile.Path` and `EnvFile.Dir` fields
- Use `filepath.base()` and `filepath.dir()` without allocation where possible

### Phase 2: Generic Table Interface

#### 2.1 Field-Based Table Renderer
```odin
Table_Field :: struct {
    name: string,
    value: string,  // String view, no allocation
    alignment: Alignment,
}

Table_Config :: struct {
    writer: io.Writer,
    fields: []Table_Field,
    col_widths: []int,
}

render_row :: proc(cfg: Table_Config, row_data: any)
```
- Accept struct fields directly without intermediate arrays
- Support field selection (show only specific fields)
- Alignment options (left/center/right)

#### 2.2 Field Extraction Procs
- Generate field extraction helpers for each struct type
- Avoid string allocation by returning string views
- Cache computed values (like formatted status strings)

#### 2.3 Streaming Table Processing
- Process rows one at a time without collecting all rows
- Reduce peak memory usage from O(N × strings) to O(table_structure)
- Enable early termination if needed

### Phase 3: Command-Specific Optimizations

#### 3.1 Eliminate Intermediate Structs
**Current (cmd_sync):**
```odin
for &file in files {
    // ... processing
    path_str, _ := strings.clone(file.Path)
    status_str, _ := strings.clone(status)
    append(&results, SyncEntry{Path = path_str, Status = status_str})
}
```

**Proposed:**
```odin
for &file in files {
    result, err_msg := db_sync(&db, &file)
    // Direct rendering with zero-copy
    render_sync_row(writer, file, result, err_msg)
}
```
- `cmd_sync`: Work directly with `EnvFile` + `SyncFlagEnum`
- `cmd_list`: Use `EnvFile` fields directly, no `ListEntry`
- Generate table content on-the-fly

#### 3.2 In-Place Status Computation
```odin
get_sync_status :: proc(result: SyncFlag, err_msg: string) -> string {
    switch {
    case .Error in result: return if len(err_msg) > 0 then err_msg else "error"
    case .BackedUp in result: return "Backed Up"
    case .Restored in result: return "Restored"
    case .DirUpdated in result: return "Moved"
    case: return "OK"
    }
}
```
- Compute status strings without allocation (use static lookup)
- Cache formatted status values if needed
- Reduce allocation count from N to 0 or 1

#### 3.3 Batch Processing
- Reduce allocation count by pooling small allocations
- Use `context.temp_allocator` more effectively
- Pre-allocate buffers for expected sizes

### Phase 4: Format-Agnostic Interface
- Commands generate data → renderers handle format
- Table renderer focuses only on ASCII/Unicode output
- Keep terminal detection in command layer

## Expected Improvements

| Metric | Current | Target | Improvement |
|--------|---------|--------|-------------|
| **Allocations** | 10+ per row | 0-1 per table | 10x+ reduction |
| **Memory copies** | 2-3 per row | 0 | 100% reduction |
| **Peak memory** | O(N × strings) | O(table_structure) | Constant factor |
| **Throughput** | Baseline | 2-3x faster | Performance boost |

## Implementation Strategy

### High-Priority Changes
1. Replace `strings.Builder` with direct `io.Writer` output
2. Convert column widths to stack-based allocation
3. Eliminate intermediate struct allocations in commands

### Medium-Priority Changes
1. Create generic field-based table interface
2. Implement streaming table processing
3. Centralize JSON rendering logic

### Low-Priority Changes
1. Add alignment options beyond left-aligned
2. Implement comprehensive field introspection
3. Add advanced table formatting features

## Tradeoff Questions

Before implementation begins, we need to resolve these architectural questions:

### 1. Generality vs. Performance
**Question:** Should we create a fully generic table renderer (similar to Zig's `Table(T)`) or focus on optimizing the current 3 use cases first?

**Options:**
- **Generic approach**: Higher development cost, future-proof, may have some overhead
- **Specific optimization**: Faster implementation, maximum performance for current use cases, less flexible

**Recommendation:** Start with specific optimizations for current use cases, then generalize patterns that emerge.

### 2. Alignment Support
**Question:** Does the project need left/center/right alignment support, or is left-alignment sufficient?

**Context:** Zig supports alignment options, but current Odin implementation only left-aligns. Most CLI tables work fine with left alignment.

**Recommendation:** Start with left-alignment only, add alignment if specific use cases demand it.

### 3. API Compatibility
**Question:** Should we maintain the current `render_table()` API signature, or are breaking changes acceptable?

**Current API:**
```odin
render_table :: proc(headers: []string, rows: [][]string)
```

**Options:**
- **Maintain API**: Slower to implement, backward compatible, may need adapter layers
- **Break API**: Faster implementation, cleaner code, requires updates to all callers

**Recommendation:** Breaking changes are acceptable since this is an optimization-focused effort and callers are limited to 3 commands.

### 4. Odin Capabilities
**Question:** What runtime reflection or field introspection capabilities does Odin provide?

**Context:** Zig uses `@typeInfo()` and comptime field iteration. We need to understand Odin's equivalent capabilities to design the optimal solution.

**Recommendation:** Investigate Odin's runtime type information capabilities before finalizing the generic table interface design.

### 5. Testing Strategy
**Question:** Should we add comprehensive tests for new table rendering before optimizing commands, or optimize incrementally with tests added afterwards?

**Options:**
- **Test-first**: More robust, catches regressions early, slower initial development
- **Optimize-first**: Faster development, may miss edge cases, requires retroactive testing

**Recommendation:** Hybrid approach - add basic tests for core infrastructure, then optimize incrementally with additional tests for each command.

## Next Steps

1. **Research Phase**: Investigate Odin's type system and reflection capabilities
2. **Prototype Phase**: Create minimal working prototype of zero-allocation table renderer
3. **Refactor Phase**: Incrementally update commands to use new infrastructure
4. **Test Phase**: Add comprehensive tests and verify memory improvements
5. **Benchmark Phase**: Measure performance improvements and memory usage

## Success Criteria

- [ ] Zero allocations for table rendering (excluding initial data)
- [ ] Zero string copies in the happy path
- [ ] All 3 commands (`list`, `sync`, `deps`) use new infrastructure
- [ ] Performance improvement of 2x or more
- [ ] Memory usage reduction of 50% or more
- [ ] No regression in table formatting quality
- [ ] Backward compatibility with JSON output format