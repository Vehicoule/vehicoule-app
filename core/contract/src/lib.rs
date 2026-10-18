//! Plugin contract: the WIT packages and their host-side bindings.

wasmtime::component::bindgen!({
    path: "wit",
    world: "probe",
    imports: { default: async },
    exports: { default: async },
});
