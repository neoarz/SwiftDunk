#include "SwiftDunkSecurity.h"
#include <TargetConditionals.h>

#if TARGET_OS_OSX
#include <Security/Security.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

int32_t swiftdunk_temporary_keychain_create(
    const char *path,
    uint32_t password_length,
    const void *password,
    void **keychain
) {
    return SecKeychainCreate(
        path,
        password_length,
        password,
        false,
        NULL,
        (SecKeychainRef *)keychain
    );
}

int32_t swiftdunk_temporary_keychain_delete(void *keychain) {
    return SecKeychainDelete((SecKeychainRef)keychain);
}

#pragma clang diagnostic pop
#else
int32_t swiftdunk_temporary_keychain_create(
    const char *path,
    uint32_t password_length,
    const void *password,
    void **keychain
) {
    (void)path;
    (void)password_length;
    (void)password;
    (void)keychain;
    return -4;
}

int32_t swiftdunk_temporary_keychain_delete(void *keychain) {
    (void)keychain;
    return -4;
}
#endif
