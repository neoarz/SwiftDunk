#if !hasFeature(InternalImportsByDefault)
    #error("InternalImportsByDefault must be enabled")
#endif

#if !hasFeature(MemberImportVisibility)
    #error("MemberImportVisibility must be enabled")
#endif

#if !hasFeature(NonisolatedNonsendingByDefault)
    #error("NonisolatedNonsendingByDefault must be enabled")
#endif

#if !hasFeature(InferIsolatedConformances)
    #error("InferIsolatedConformances must be enabled")
#endif
