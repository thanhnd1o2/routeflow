//! FFI layer exposing the rule engine to Swift via C-compatible functions.
//!
//! All functions use C-compatible types and follow these conventions:
//! - Strings are passed as null-terminated C strings (`*const c_char`)
//! - Returned strings must be freed by the caller using `routeflow_free_string`
//! - The engine handle is an opaque pointer

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;
use std::ptr;

use crate::config::Config;
use crate::rule_engine::RuleEngine;

/// Opaque handle to the rule engine.
pub struct RouteFlowEngine {
    engine: RuleEngine,
}

/// Create a new RouteFlow engine from a YAML config file path.
/// Returns null on failure.
///
/// # Safety
/// `config_path` must be a valid null-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn routeflow_engine_create_from_file(
    config_path: *const c_char,
) -> *mut RouteFlowEngine {
    if config_path.is_null() {
        return ptr::null_mut();
    }

    let path_str = match CStr::from_ptr(config_path).to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let config = match Config::from_file(Path::new(path_str)) {
        Ok(c) => c,
        Err(_) => return ptr::null_mut(),
    };

    let engine = match RuleEngine::from_config(&config) {
        Ok(e) => e,
        Err(_) => return ptr::null_mut(),
    };

    Box::into_raw(Box::new(RouteFlowEngine { engine }))
}

/// Create a new RouteFlow engine from a YAML config string.
/// Returns null on failure.
///
/// # Safety
/// `config_yaml` must be a valid null-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn routeflow_engine_create_from_string(
    config_yaml: *const c_char,
) -> *mut RouteFlowEngine {
    if config_yaml.is_null() {
        return ptr::null_mut();
    }

    let yaml_str = match CStr::from_ptr(config_yaml).to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let config = match Config::from_str(yaml_str) {
        Ok(c) => c,
        Err(_) => return ptr::null_mut(),
    };

    let engine = match RuleEngine::from_config(&config) {
        Ok(e) => e,
        Err(_) => return ptr::null_mut(),
    };

    Box::into_raw(Box::new(RouteFlowEngine { engine }))
}

/// Resolve a domain to an interface name.
/// Returns a newly allocated C string that must be freed with `routeflow_free_string`.
/// Returns null if the engine pointer or domain is invalid.
///
/// # Safety
/// - `engine` must be a valid pointer from `routeflow_engine_create_*`
/// - `domain` must be a valid null-terminated C string
#[no_mangle]
pub unsafe extern "C" fn routeflow_resolve(
    engine: *const RouteFlowEngine,
    domain: *const c_char,
) -> *mut c_char {
    if engine.is_null() || domain.is_null() {
        return ptr::null_mut();
    }

    let domain_str = match CStr::from_ptr(domain).to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let decision = (*engine).engine.resolve(domain_str);

    match CString::new(decision.interface) {
        Ok(cs) => cs.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Resolve a domain and return the matched rule description.
/// Returns a newly allocated C string that must be freed with `routeflow_free_string`.
/// Returns null if no rule matched (default was used) or on error.
///
/// # Safety
/// - `engine` must be a valid pointer from `routeflow_engine_create_*`
/// - `domain` must be a valid null-terminated C string
#[no_mangle]
pub unsafe extern "C" fn routeflow_resolve_rule(
    engine: *const RouteFlowEngine,
    domain: *const c_char,
) -> *mut c_char {
    if engine.is_null() || domain.is_null() {
        return ptr::null_mut();
    }

    let domain_str = match CStr::from_ptr(domain).to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let decision = (*engine).engine.resolve(domain_str);

    match decision.matched_rule {
        Some(rule) => match CString::new(rule) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        None => ptr::null_mut(),
    }
}

/// Get the number of rules loaded in the engine.
///
/// # Safety
/// `engine` must be a valid pointer from `routeflow_engine_create_*`.
#[no_mangle]
pub unsafe extern "C" fn routeflow_rule_count(engine: *const RouteFlowEngine) -> usize {
    if engine.is_null() {
        return 0;
    }
    (*engine).engine.rule_count()
}

/// Get the default interface name.
/// Returns a newly allocated C string that must be freed with `routeflow_free_string`.
///
/// # Safety
/// `engine` must be a valid pointer from `routeflow_engine_create_*`.
#[no_mangle]
pub unsafe extern "C" fn routeflow_default_interface(
    engine: *const RouteFlowEngine,
) -> *mut c_char {
    if engine.is_null() {
        return ptr::null_mut();
    }

    let iface = (*engine).engine.default_interface();
    match CString::new(iface) {
        Ok(cs) => cs.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Free a string returned by any `routeflow_*` function.
///
/// # Safety
/// `s` must be a pointer previously returned by a `routeflow_*` function, or null.
#[no_mangle]
pub unsafe extern "C" fn routeflow_free_string(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Destroy a RouteFlow engine and free its memory.
///
/// # Safety
/// `engine` must be a pointer previously returned by `routeflow_engine_create_*`, or null.
#[no_mangle]
pub unsafe extern "C" fn routeflow_engine_destroy(engine: *mut RouteFlowEngine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    const TEST_YAML: &str = "interfaces:\n  - name: wifi\n    type: wifi\n  - name: ethernet\n    type: ethernet\nrules:\n  - DOMAIN-SUFFIX,github.com,wifi\n  - DOMAIN-SUFFIX,company.com,ethernet\ndefault: wifi\n";

    #[test]
    fn test_ffi_create_and_resolve() {
        unsafe {
            let yaml = CString::new(TEST_YAML).unwrap();
            let engine = routeflow_engine_create_from_string(yaml.as_ptr());
            assert!(!engine.is_null());

            let domain = CString::new("api.github.com").unwrap();
            let result = routeflow_resolve(engine, domain.as_ptr());
            assert!(!result.is_null());

            let iface = CStr::from_ptr(result).to_str().unwrap();
            assert_eq!(iface, "wifi");
            routeflow_free_string(result);

            let domain2 = CString::new("mail.company.com").unwrap();
            let result2 = routeflow_resolve(engine, domain2.as_ptr());
            let iface2 = CStr::from_ptr(result2).to_str().unwrap();
            assert_eq!(iface2, "ethernet");
            routeflow_free_string(result2);

            assert_eq!(routeflow_rule_count(engine), 2);

            routeflow_engine_destroy(engine);
        }
    }

    #[test]
    fn test_ffi_null_safety() {
        unsafe {
            let result = routeflow_resolve(ptr::null(), ptr::null());
            assert!(result.is_null());

            let engine = routeflow_engine_create_from_string(ptr::null());
            assert!(engine.is_null());

            // Should not crash
            routeflow_free_string(ptr::null_mut());
            routeflow_engine_destroy(ptr::null_mut());
        }
    }
}
