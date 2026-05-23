/*
 * WAGOTHook.m
 *
 * Hooks WhatsApp C functions via Mach-O GOT (import table) rebinding.
 * This approach works even when symbols are not exported from SharedModules,
 * because it patches the call sites in the importing image rather than the
 * function definition.
 *
 * Adapted from https://github.com/espotty/wafix (MIT)
 */

#import <Foundation/Foundation.h>

#include <stdint.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>

// Defined in Tweak.xm — set before wa_got_hook_apply() is called.
extern int        newVersionMajor;
extern int        newVersionMinor;
extern int        newVersionBuild;
extern int        newVersionRevision;
extern NSString  *newVersion;
extern NSString  *spoofedUserAgent;
extern BOOL       debugLogging;

static NSDate *g_futureDate = nil;

// ── Replacement functions ────────────────────────────────────────────────────

static id   got_WABuildVersion(void)                         { return newVersion; }
static id   got_WABuildHTTPUserAgentString(void)             { return spoofedUserAgent; }
static int  got_WAIsAfterDeprecatedPlatformCutoffDate(void)  { return 0; }
static id   got_WADeprecatedPlatformCutOffDate(void)         { return g_futureDate; }
static int  got_WABuildVersionComponent1(void)               { return newVersionMajor; }
static int  got_WABuildVersionComponent2(void)               { return newVersionMinor; }
static int  got_WABuildVersionComponent3(void)               { return newVersionBuild; }
static int  got_WABuildVersionComponent4(void)               { return newVersionRevision; }
static void got_WAHandleFailureInFunction(void)              {}
// Hook abort() in SharedModules' GOT so WAHandleFailureInFunction can't escape via it.
static void got_abort(void)                                  {}
static void got_assert_rtn(void)                             {}

// ── Hook table ───────────────────────────────────────────────────────────────

struct hook_entry { const char *name; void *replacement; };

static struct hook_entry g_hooks[] = {
    { "_WAHandleFailureInFunction",             (void*)got_WAHandleFailureInFunction },
    { "_WAIsAfterDeprecatedPlatformCutoffDate", (void*)got_WAIsAfterDeprecatedPlatformCutoffDate },
    { "_WADeprecatedPlatformCutOffDate",        (void*)got_WADeprecatedPlatformCutOffDate },
    { "_WABuildVersion",                        (void*)got_WABuildVersion },
    { "_WABuildHTTPUserAgentString",            (void*)got_WABuildHTTPUserAgentString },
    { "_WABuildVersionComponent1",              (void*)got_WABuildVersionComponent1 },
    { "_WABuildVersionComponent2",              (void*)got_WABuildVersionComponent2 },
    { "_WABuildVersionComponent3",              (void*)got_WABuildVersionComponent3 },
    { "_WABuildVersionComponent4",              (void*)got_WABuildVersionComponent4 },
    { "_abort",                                 (void*)got_abort },
    { "___assert_rtn",                          (void*)got_assert_rtn },
};
#define N_HOOKS ((int)(sizeof(g_hooks) / sizeof(g_hooks[0])))

// ── Helpers ──────────────────────────────────────────────────────────────────

static int name_match(const char *sym, const char *target) {
    if (!sym || !target) return 0;
    while (*target) { if (*sym != *target) return 0; sym++; target++; }
    return *sym == '\0';
}

// ── Mach-O GOT rebinding ─────────────────────────────────────────────────────

static void rebind_imports_in_image(const struct mach_header_64 *header, intptr_t slide) {
    if (!header || header->magic != MH_MAGIC_64) return;
    if (header->ncmds == 0 || header->ncmds > 4096) return;

    const struct load_command *lc =
        (const struct load_command *)((uintptr_t)header + sizeof(struct mach_header_64));

    const struct symtab_command   *symtab_cmd  = NULL;
    const struct dysymtab_command *dysymtab_cmd = NULL;
    uint64_t linkedit_vmaddr = 0, linkedit_fileoff = 0, text_vmaddr = 0;
    int found_le = 0, found_tx = 0;

    struct { uint64_t addr; uint64_t size; uint32_t reserved1; } sects[64];
    int n_sects = 0;

    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (!lc || lc->cmdsize < 8) return;

        if (lc->cmd == LC_SYMTAB && lc->cmdsize >= sizeof(struct symtab_command)) {
            symtab_cmd = (const struct symtab_command *)lc;
        }
        else if (lc->cmd == LC_DYSYMTAB && lc->cmdsize >= sizeof(struct dysymtab_command)) {
            dysymtab_cmd = (const struct dysymtab_command *)lc;
        }
        else if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (seg->segname[0] != '_' || seg->segname[1] != '_') goto next;

            if (seg->segname[2]=='L' && seg->segname[3]=='I' &&
                seg->segname[4]=='N' && seg->segname[5]=='K' && seg->segname[6]=='E') {
                linkedit_vmaddr  = seg->vmaddr;
                linkedit_fileoff = seg->fileoff;
                found_le = 1;
            }
            else if (seg->segname[2]=='T' && seg->segname[3]=='E' &&
                     seg->segname[4]=='X' && seg->segname[5]=='T' && seg->segname[6]=='\0') {
                text_vmaddr = seg->vmaddr;
                found_tx = 1;
            }
            else if (seg->segname[2]=='D' && seg->segname[3]=='A' &&
                     seg->segname[4]=='T' && seg->segname[5]=='A') {
                if (seg->nsects > 256) goto next;
                const struct section_64 *sec =
                    (const struct section_64 *)((uintptr_t)seg + sizeof(struct segment_command_64));
                for (uint32_t j = 0; j < seg->nsects && n_sects < 64; j++) {
                    uint32_t type = sec[j].flags & SECTION_TYPE;
                    if (type == S_NON_LAZY_SYMBOL_POINTERS || type == S_LAZY_SYMBOL_POINTERS) {
                        sects[n_sects].addr      = sec[j].addr;
                        sects[n_sects].size      = sec[j].size;
                        sects[n_sects].reserved1 = sec[j].reserved1;
                        n_sects++;
                    }
                }
            }
        }
    next:
        lc = (const struct load_command *)((uintptr_t)lc + lc->cmdsize);
    }

    if (!symtab_cmd || !dysymtab_cmd || !found_le || !found_tx) return;
    if (symtab_cmd->nsyms == 0 || symtab_cmd->strsize == 0) return;
    if (dysymtab_cmd->nindirectsyms == 0 || n_sects == 0) return;
    if (linkedit_vmaddr < text_vmaddr) return;
    if (symtab_cmd->symoff < linkedit_fileoff) return;
    if (symtab_cmd->stroff < linkedit_fileoff) return;
    if (dysymtab_cmd->indirectsymoff < linkedit_fileoff) return;

    uintptr_t le_base = (uintptr_t)header + (linkedit_vmaddr - text_vmaddr);
    const struct nlist_64 *nlist   = (const struct nlist_64 *)(le_base + (symtab_cmd->symoff   - linkedit_fileoff));
    const char            *strtab  = (const char *)            (le_base + (symtab_cmd->stroff   - linkedit_fileoff));
    const uint32_t        *indsyms = (const uint32_t *)        (le_base + (dysymtab_cmd->indirectsymoff - linkedit_fileoff));

    uint32_t nsyms   = symtab_cmd->nsyms;
    uint32_t strsize = symtab_cmd->strsize;
    uint32_t ninds   = dysymtab_cmd->nindirectsyms;

    for (int s = 0; s < n_sects; s++) {
        if (sects[s].size == 0) continue;
        uint32_t n_entries = (uint32_t)(sects[s].size / sizeof(void*));
        void    **ptrs     = (void **)((uintptr_t)sects[s].addr + (uintptr_t)slide);
        uint32_t  base     = sects[s].reserved1;

        for (uint32_t e = 0; e < n_entries; e++) {
            uint32_t pos = base + e;
            if (pos >= ninds) break;

            uint32_t sym_idx = indsyms[pos];
            if (sym_idx & (INDIRECT_SYMBOL_ABS | INDIRECT_SYMBOL_LOCAL)) continue;
            if (sym_idx >= nsyms) continue;

            uint32_t strx = nlist[sym_idx].n_un.n_strx;
            if (strx == 0 || strx >= strsize) continue;

            const char *sn = strtab + strx;
            if (sn[0] != '_') continue;

            for (int h = 0; h < N_HOOKS; h++) {
                if (name_match(sn, g_hooks[h].name)) {
                    ptrs[e] = g_hooks[h].replacement;
                    if (debugLogging)
                        NSLog(@"[Phantom GOT] Patched %s in image", g_hooks[h].name);
                    break;
                }
            }
        }
    }
}

// Called by dyld for every image — both already-loaded and future ones.
// Using _dyld_register_func_for_add_image ensures we catch SharedModules
// even if it loads after our constructor runs (DYLD_INSERT_LIBRARIES order).
static void on_image_added(const struct mach_header *mh, intptr_t slide) {
    rebind_imports_in_image((const struct mach_header_64 *)mh, slide);
}

// ── Public entry point ────────────────────────────────────────────────────────

void wa_got_hook_apply(void) {
    g_futureDate = [NSDate dateWithTimeIntervalSinceNow: 315360000.0];
    // Registers callback for all currently-loaded images AND any image loaded later.
    // This guarantees hooks apply to SharedModules regardless of load order.
    _dyld_register_func_for_add_image(on_image_added);
}
