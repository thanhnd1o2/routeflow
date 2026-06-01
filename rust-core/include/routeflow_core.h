#include <cstdarg>
#include <cstdint>
#include <cstdlib>
#include <ostream>
#include <new>

/// Opaque handle to the rule engine.
struct RouteFlowEngine;

extern "C" {

/// Create a new RouteFlow engine from a YAML config file path.
/// Returns null on failure.
///
/// # Safety
/// `config_path` must be a valid null-terminated C string.
RouteFlowEngine *routeflow_engine_create_from_file(const char *config_path);

/// Create a new RouteFlow engine from a YAML config string.
/// Returns null on failure.
///
/// # Safety
/// `config_yaml` must be a valid null-terminated C string.
RouteFlowEngine *routeflow_engine_create_from_string(const char *config_yaml);

/// Resolve a domain to an interface name.
/// Returns a newly allocated C string that must be freed with `routeflow_free_string`.
/// Returns null if the engine pointer or domain is invalid.
///
/// # Safety
/// - `engine` must be a valid pointer from `routeflow_engine_create_*`
/// - `domain` must be a valid null-terminated C string
char *routeflow_resolve(const RouteFlowEngine *engine, const char *domain);

/// Resolve a domain and return the matched rule description.
/// Returns a newly allocated C string that must be freed with `routeflow_free_string`.
/// Returns null if no rule matched (default was used) or on error.
///
/// # Safety
/// - `engine` must be a valid pointer from `routeflow_engine_create_*`
/// - `domain` must be a valid null-terminated C string
char *routeflow_resolve_rule(const RouteFlowEngine *engine, const char *domain);

/// Get the number of rules loaded in the engine.
///
/// # Safety
/// `engine` must be a valid pointer from `routeflow_engine_create_*`.
uintptr_t routeflow_rule_count(const RouteFlowEngine *engine);

/// Get the default interface name.
/// Returns a newly allocated C string that must be freed with `routeflow_free_string`.
///
/// # Safety
/// `engine` must be a valid pointer from `routeflow_engine_create_*`.
char *routeflow_default_interface(const RouteFlowEngine *engine);

/// Free a string returned by any `routeflow_*` function.
///
/// # Safety
/// `s` must be a pointer previously returned by a `routeflow_*` function, or null.
void routeflow_free_string(char *s);

/// Destroy a RouteFlow engine and free its memory.
///
/// # Safety
/// `engine` must be a pointer previously returned by `routeflow_engine_create_*`, or null.
void routeflow_engine_destroy(RouteFlowEngine *engine);

}  // extern "C"
