#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <libkern/OSCacheControl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#if defined(__arm64__) || defined(__aarch64__)
static const uint8_t kArm64Signature[] = {
    0x08, 0x0C, 0x40, 0xB9,
    0x49, 0xE2, 0x84, 0x52,
    0x1F, 0x01, 0x09, 0x6B,
    0xE0, 0x17, 0x9F, 0x1A,
    0xC0, 0x03, 0x5F, 0xD6,
};
#elif defined(__x86_64__)

static const uint8_t kX86Signature[] = {
    0x55, 0x48, 0x89, 0xE5,
    0x81, 0x7F, 0x0C, 0x12, 0x27, 0x00, 0x00,
    0x0F, 0x94, 0xC0,
    0x5D, 0xC3,
};
#endif

static void write_log(const char *message) {
    FILE *file = fopen("/tmp/wechatguard-hook.log", "a");
    if (file == NULL) {
        return;
    }
    fprintf(file, "[WeChatGuard] %s\n", message);
    fclose(file);
}

static int find_main_text(uintptr_t *start, size_t *size) {
    const struct mach_header *header = _dyld_get_image_header(0);
    if (header == NULL || header->magic != MH_MAGIC_64) {
        return 0;
    }

    const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
    const uint8_t *cursor = (const uint8_t *)header64 + sizeof(struct mach_header_64);
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);

    for (uint32_t index = 0; index < header64->ncmds; index++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
            const struct section_64 *sections = (const struct section_64 *)(segment + 1);
            for (uint32_t sectionIndex = 0; sectionIndex < segment->nsects; sectionIndex++) {
                const struct section_64 *section = &sections[sectionIndex];
                if (strncmp(section->segname, "__TEXT", 16) == 0 &&
                    strncmp(section->sectname, "__text", 16) == 0) {
                    *start = (uintptr_t)(section->addr + slide);
                    *size = (size_t)section->size;
                    return 1;
                }
            }
        }
        if (command->cmdsize < sizeof(struct load_command)) {
            return 0;
        }
        cursor += command->cmdsize;
    }
    return 0;
}

static uintptr_t find_unique_signature(
    uintptr_t start,
    size_t size,
    const uint8_t *signature,
    size_t signatureSize
) {
    uintptr_t match = 0;
    size_t matches = 0;
    if (size < signatureSize) {
        return 0;
    }
    for (size_t offset = 0; offset <= size - signatureSize; offset++) {
        const uint8_t *candidate = (const uint8_t *)(start + offset);
        if (candidate[0] == signature[0] && memcmp(candidate, signature, signatureSize) == 0) {
            match = start + offset;
            matches++;
            if (matches > 1) {
                return 0;
            }
        }
    }
    return matches == 1 ? match : 0;
}

static int make_writable(uintptr_t address, size_t length, mach_vm_address_t *page, mach_vm_size_t *pageSize) {
    vm_size_t systemPageSize = 0;
    if (host_page_size(mach_host_self(), &systemPageSize) != KERN_SUCCESS || systemPageSize == 0) {
        return 0;
    }
    *page = (mach_vm_address_t)(address & ~((uintptr_t)systemPageSize - 1));
    uintptr_t end = (address + length + systemPageSize - 1) & ~((uintptr_t)systemPageSize - 1);
    *pageSize = (mach_vm_size_t)(end - *page);
    kern_return_t result = mach_vm_protect(
        mach_task_self(),
        *page,
        *pageSize,
        0,
        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY
    );
    return result == KERN_SUCCESS;
}

static int patch_revoke_check(uintptr_t address) {
    mach_vm_address_t page = 0;
    mach_vm_size_t pageSize = 0;
#if defined(__arm64__) || defined(__aarch64__)
    const size_t patchSize = 8;
#elif defined(__x86_64__)
    const size_t patchSize = 16;
#else
    return 0;
#endif
    if (!make_writable(address, patchSize, &page, &pageSize)) {
        return 0;
    }

#if defined(__arm64__) || defined(__aarch64__)
    uint32_t *instructions = (uint32_t *)address;
    instructions[0] = 0x52800000U;
    instructions[1] = 0xD65F03C0U;
    sys_icache_invalidate((void *)address, patchSize);
#elif defined(__x86_64__)
    uint8_t patch[16] = {
        0x31, 0xC0, 0xC3,
        0x90, 0x90, 0x90, 0x90, 0x90,
        0x90, 0x90, 0x90, 0x90, 0x90,
        0x90, 0x90, 0x90,
    };
    memcpy((void *)address, patch, sizeof(patch));
    __builtin___clear_cache((char *)address, (char *)(address + patchSize));
#endif

    kern_return_t result = mach_vm_protect(
        mach_task_self(),
        page,
        pageSize,
        0,
        VM_PROT_READ | VM_PROT_EXECUTE
    );
    return result == KERN_SUCCESS;
}

__attribute__((constructor))
static void wechatguard_initialize(void) {
    uintptr_t textStart = 0;
    size_t textSize = 0;
    if (!find_main_text(&textStart, &textSize)) {
        write_log("failed: main __TEXT,__text section not found");
        return;
    }

#if defined(__arm64__) || defined(__aarch64__)
    uintptr_t match = find_unique_signature(
        textStart, textSize, kArm64Signature, sizeof(kArm64Signature)
    );
#elif defined(__x86_64__)
    uintptr_t match = find_unique_signature(
        textStart, textSize, kX86Signature, sizeof(kX86Signature)
    );
#else
    uintptr_t match = 0;
#endif

    if (match == 0) {
        write_log("failed: anti-revoke signature was not unique");
        return;
    }
    if (!patch_revoke_check(match)) {
        write_log("failed: runtime code patch was denied");
        return;
    }
    write_log("ready: anti-revoke check disabled");
}
