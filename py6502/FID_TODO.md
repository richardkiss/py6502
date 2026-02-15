# FID (File Developer) Reverse-Engineering TODO

## Current State

**File:** `6502-prog.asm` (2,390 lines, 64,516 bytes)  
**Status:** ✅ Round-trip verified (4686/4686 bytes match original)  
**Overall Completion:** ~48% code documented (handlers phase), ~99% architecture understood
**Last Updated:** Phase 6 complete

### Quick Stats
- Lines of code: 2,390 total
- Documented: 1,142 lines (48%)
- Undocumented: 1,248 lines (52%)
- Handlers documented: 2 of 8 (25%)

### Verification
```bash
cd py6502
python3 py6502/cli_asm6502.py 6502-prog.asm -b /tmp/test.bin --compare 6502-prog_noheader.bin
```

---

## Completed Phases ✅

**Phase 1-6**: String conversion, data structures, subroutine headers, inline comments, branch annotations, flow documentation.

See `PHASE_6_SESSION_SUMMARY.md` for detailed history.

---

## Phase 7: Operation Handler Implementation Documentation ⏳

### Overview
8 operation handlers (~400 lines) and supporting utilities (~867 lines). Core functionality of FID.

**Progress:** 2 of 8 handlers documented (LOCK, UNLOCK)

### 7.1 LOCK Handler ($0D84) - ✅ COMPLETE
**Status:** DOCUMENTED  
**Completion Date:** Current session  
**Documentation Details:**
- Full instruction-by-instruction comments added
- Explained BIT instruction and N flag behavior
- Documented FILE_STATUS bit 7 (lock flag) semantics
- Operation flow: test → check → execute → display message
- Binary verification: $0D84-$0D96 (19 bytes)
- Exit behavior: Returns via RTS to menu loop
- Related error condition: BMI branch for already-locked files

**Pattern Established:**
This handler serves as the template for remaining handlers. Pattern:
1. Test/load operation parameters
2. Store operation code in DOS FM parameter block ($18F9)
3. Call subroutine $1266 to execute DOS operation
4. Display result message (string index 14)
5. Return via RTS

### 7.2 UNLOCK Handler ($0D97) - ✅ COMPLETE
**Status:** DOCUMENTED  
**Completion Date:** Current session  
**Documentation Details:**
- Opposite logic of LOCK handler (BPL instead of BMI)
- Tests if file is NOT locked (branch if Plus, N=0)
- Operation code $08 for DOS file manager
- Clears bit 7 in FILE_STATUS to remove write-protection
- Error path: Shows message if file wasn't locked
- Binary matches: $0D97-$0DA9 (19 bytes)

### 7.3 DELETE Handler ($0D69) - ⏳ TODO
**Complexity:** ⭐⭐ Moderate  
**Task:**
- Modify catalog entry (zero filename)
- Update sector bitmap to mark sectors as free
- Follow file's T/S list if multi-sector file
- Expected: ~40-50 bytes of code

### 7.4 VERIFY Handler ($0DBE)
**Lines:** ~50-60  
**Complexity:** ⭐⭐ Moderate  
**Task:**
- Traverse file's T/S list
- Verify each sector is readable
- Report errors without modifying file

### 7.5 COPY Handler ($0E66)
**Complexity:** ⭐⭐⭐⭐⭐ Very Complex  
**Expected Size:** ~100-150 bytes  
**Task:**
- Read source file sector by sector into buffer
- Write each sector to destination disk/location
- Handle SAME_DISK_FLAG for disk swap prompts
- Preserve file type and attributes
- Complex multi-sector file handling

### 7.6 CATALOG Handler ($0DAA)
**Lines:** ~80-100  
**Complexity:** ⭐⭐⭐ Complex  
**Task:**
- Format file entries for display
- Interpret format codes ($80-$9D)
- Display filename, type, size, sectors, lock status

### 7.7 SPACE Handler ($0DD8)
**Lines:** ~60-80  
**Complexity:** ⭐⭐⭐ Complex  
**Task:**
- Read sector bitmap from track $11
- Count free vs used sectors
- Display in BCD format

### 7.8 RESET Handler ($0DB3)
**Lines:** ~20-30  
**Complexity:** ⭐ Easy  
**Task:** Update default slot/drive variables

---

## Phase 8: Supporting Code Documentation ⏳

### 8.1 Wildcard Matching Implementation
**Lines:** ~200  
**Current Status:** High-level flow documented in `PHASE_6_FLOW_DIAGRAMS.md`, implementation needs documentation  
**Task:** Document forward/backward scanning register operations and state tracking

### 8.2 DOS File Manager Integration
**Lines:** ~100  
**Task:**
- Parameter block construction
- DOS call invocation ($03D6)
- Error code interpretation

### 8.3 Utility Functions
**Lines:** ~500-600  
**Task:**
- Sector reading/writing wrappers
- Buffer management
- Register save/restore patterns
- Address calculations

### 8.4 BCD Arithmetic & Bit Operations
**Lines:** ~150-200  
**Task:**
- SED/CED (decimal mode) operations for sector counting
- Bit shifting for file size calculations
- Bitmap bit manipulation

---

## Documentation Resources Created

✅ **PHASE_6_FLOW_DIAGRAMS.md** - Architecture diagrams
- Main menu loop, RTS dispatch, file operations pipeline
- Wildcard matching state machine, memory layout
- Variable dependency graph

✅ **PHASE_6_SESSION_SUMMARY.md** - Session analysis
- Documentation paradox explanation
- Realistic timeline (95-120 hours total)
- Key insights and recommendations

---

## Recommended Approach

1. **✅ Complete simple handlers** (7.1, 7.2 - DONE)
   - LOCK: Test bit → execute → message → return
   - UNLOCK: Opposite of LOCK
   - Pattern established for remaining handlers
   
2. **Next: Easy handlers** (7.8 RESET, ~1 hour)
   - No state testing, pure parameter update
   - Simple message display
   
3. **Then: Moderate handlers** (7.3 DELETE, 7.4 VERIFY, ~3-4 hours)
   - Require sector/catalog manipulation
   - More complex DOS integration
   
4. **Complex handlers last** (7.6 CATALOG, 7.7 SPACE, ~4-6 hours)
   - Sector bitmap scanning
   - Format code interpretation
   - Multi-sector file handling
   
5. **Most complex: COPY** (7.5, ~8-10 hours)
   - Disk swap logic
   - Source/destination handling
   - Sector-by-sector file copying
   
6. **Document supporting code** (Phase 8)
   - Wildcard matching
   - DOS integration subroutines
   - Utility functions

7. **Final polish**
   - Cross-references
   - Quick-reference guides
   - Full verification

---

## Project Timeline

- **Current:** 7 sessions, ~21 hours, 35% code documented
- **Phase 7 Progress:** 2/8 handlers complete (LOCK, UNLOCK) (~1.5 hours)
- **Phase 7 Remaining:** ~6 handlers, est. 25-40 hours
- **Phase 8:** Estimated 5-10 sessions, ~15-30 hours
- **Polish:** Estimated 2-3 sessions, ~6-9 hours
- **Revised Total:** ~85-110 hours, 2-3 months at steady pace

---

## Files & Tools

**Main Working File:**
- `6502-prog.asm` - Current development version

**Reference/Phase Artifacts:**
- `6502-prog-annotated.asm` - Phase 5.2 branch annotations

**Documentation:**
- `PHASE_6_FLOW_DIAGRAMS.md` - Architecture diagrams
- `PHASE_6_SESSION_SUMMARY.md` - Session findings
- `CLEANUP_SUMMARY.md` - Project cleanup notes
- `DOCUMENTATION_INDEX.md` - Doc guide
- `QUICK_REFERENCE.md` - Quick lookup

**Tools Created:**
- `annotate_branches.py` - Phase 5.2 branch annotation tool
- `convert_strings_to_macros.py` - String macro converter
- `simplify_string_comments.py` - Comment cleanup
- `cli_asm6502.py` - Main assembler

---

## Session Checklist - Phase 7.1 ✅ COMPLETE

- [x] Understand LOCK handler location ($0D84) in assembly
- [x] Document LOCK handler with full inline comments
- [x] Document UNLOCK handler (bonus - found adjacent)
- [x] Add structural section headers for all 8 handlers
- [x] Add comprehensive operation flow documentation
- [x] Verify binary still matches (4686 bytes) ✓
- [x] Update FID_TODO.md with progress

## Next Session Checklist - Phase 7.3 (DELETE Handler)

- [ ] Review DELETE handler code at $0D69
- [ ] Understand catalog entry structure
- [ ] Document sector bitmap manipulation logic
- [ ] Trace T/S list following for multi-sector files
- [ ] Verify binary still matches after documentation
- [ ] Update progress in FID_TODO.md

---

## Success Criteria

Phase 7 complete when:
- All 8 operation handlers fully documented
- Every instruction explained
- All register usage documented
- Error paths explained
- Binary still matches 100%

---

**Status:** Phase 7.1 COMPLETE, Ready for Phase 7.3  
**Current Phase:** 7.3 - DELETE Handler Documentation  
**Last Completed:** 7.1 (LOCK), 7.2 (UNLOCK - documented together)
**Estimated Time for 7.3:** 1-2 hours  
**Priority:** High (core file operations)