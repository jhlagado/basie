# Overlay phase exploration

Date: 2026-10-06
Baseline: 77b3e94
Status: source-traced first exploration, no implementation change or measured candidate saving

John requests an examination of compiler phases to find opportunities to move more core code into overlays, including whether a larger window would produce a net RAM saving. A smaller COM alone is not the acceptance criterion. The current recorded image is 19,653 bytes and the overlay area 2,483 bytes, totalling 22,136 bytes before workspace, source and stack.

## Observed phase boundaries

| Phase | Current code and data | Lifetime and opportunity |
| --- | --- | --- |
| Command and options | COMMAND overlay | Runs once, then discarded. Already offloaded. |
| Runtime library validation | START overlay | Runs before source loading. Returns to the resident shell. |
| Source and include loading | PARTS overlay | Runs before compilation, recursively loading includes. Already offloaded. Future source streaming changes this boundary. |
| Output streams and part records | START overlay, second entry | Runs once after parts load. Already offloaded. |
| Declaration and routine compilation | Resident parser, expression islands, actions, generators, symbol and type operations; NAMES overlay | Interleaved during the single pass, not independent whole-program passes. Splitting these modules by filename does not establish safe swap boundaries. |
| Floating-point literals and folding | FLOAT above NAMES | Loaded when first needed and kept. NAMES must coexist for name lookup. |
| Completed routine finalisation | RG_CLOSE, BL_SHORT, BL_END | The strongest additional boundary found: generation has finished, then branch selection and blob serialisation operate on retained bytes and metadata. |
| Completed data object publication | BL_END, called by data and pool writers | Serialisation is also used outside routine finalisation, so a publication overlay would load more often than once per routine. |
| End of compilation | CHAIN overlay, CH_DONE | Closes streams and chains to BLINK unless compile-only. Already offloaded. |
| Diagnostic and failure | DIAG overlay after abandoning parsing | Terminal path. Parser diagnostics restore PR_SP and return to the shell, so parsing does not resume into overwritten code. Already offloaded. |

The shell sequence is explicit in SHELL.ASM. GENCALL.ASM's routine close appends its frame/need words and literals, calls BL_SHORT, then BL_END, then writes its name and deferred aggregate constants. BLOB.ASM's BL_END serialises references, code bytes and line entries, applying BL_MAP to shrinking-adjusted offsets. POOLS.ASM also calls BL_END while publishing pool information and ownership descriptors.

## First candidate: finalisation and publication

Investigate one overlay containing branch shrinking and blob serialisation, including the shared offset mapping and serialisation helpers they require. Combining them is preferable to loading a shrinker, immediately replacing it with a writer and recreating dependencies between the two.

Retain the incremental construction operations used during parsing, stream buffers and their pointers, output I/O, labels, routine metadata and other live state in resident storage. A resident entry must load the finalisation overlay, call it and return to resident code. No continuation may point into the replaced overlay. Its failure paths must reach resident error handling safely.

Two layouts should be compared. Loading above NAMES would preserve its 947 bytes but replace FLOAT. Reusing the complete window could provide more room but requires reloading NAMES before the next lookup. Both can require reloading FLOAT when the next floating-point token or fold occurs. The current loader tracks only the last overlay ID (OV_CUR), so this needs explicit validity handling for overlapping regions rather than treating an ID as proof that all bytes remain present.

This could incur swaps per routine or data object. A float-heavy source with many short routines is a necessary adverse case. Large routines may amortise the reads much better. The candidate is not proven to fit the existing area and its full dependency closure has not yet been measured.

## Other candidates

Ownership descriptor generation is a declaration-time walk that emits read-only data. Its payload sizes, type traversal helpers and interleaving with declaration parsing need inspection before treating it as independent. Startup and shutdown have already moved most obvious one-shot work out of the image, so simply repeating that categorisation will miss the new opportunity.

Splitting expression parsing from statement parsing is a higher-frequency alternative. These nest through arguments, indices and calls, and retain return addresses to their active code. A safe implementation would need resident dispatch or restructuring and may generate disk traffic per statement. Keep this as a later candidate rather than assume every module can be independently paged.

## When a larger window helps

Let R be the resident bytes removed, G the window growth and T the new resident loader or dispatch code. Net resident-plus-window saving is R minus G minus T. Overlay file growth is accounted for separately. A larger window can be worthwhile when it permits several mutually exclusive large phases to share it. Expanding it for one offloaded block alone can erase most of the benefit.

Evaluate at least the existing 2,483-byte area and one or more larger layouts selected from measured dependency closures. Include resident tables duplicated into overlays, alignment and 128-byte read padding, writable state, stack, free source space and future streaming changes. Respect D46: restart vectors remain with the platform.

## Next proof required

Measure the assembled byte ranges of finalisation and descriptor candidates, trace their complete callees and live return addresses, then propose concrete placement and invalidation rules. Compare unchanged compiler output and diagnostics on the existing equivalence corpus. Count overlay loads and records read for small, large and float-heavy multi-routine programs, with explicit disk-latency assumptions. Report COM reduction, net RAM saving and the worst observed load frequency. No benefit or performance claim is established by this first source trace alone.
