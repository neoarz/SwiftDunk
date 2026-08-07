#ifndef SWIFTDUNK_SECURITY_H
#define SWIFTDUNK_SECURITY_H

#include <stdint.h>

int32_t swiftdunk_temporary_keychain_create(
    const char *path,
    uint32_t password_length,
    const void *password,
    void **keychain
);

int32_t swiftdunk_temporary_keychain_delete(void *keychain);

#endif
