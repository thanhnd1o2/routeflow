/* RouteFlow Core C API - Swift Bridging Header */

#ifndef ROUTEFLOW_CORE_H
#define ROUTEFLOW_CORE_H

#include <stdint.h>
#include <stddef.h>

/* Opaque handle to the rule engine */
typedef struct RouteFlowEngine RouteFlowEngine;

/* Create a new engine from a YAML config file path. Returns NULL on failure. */
RouteFlowEngine *routeflow_engine_create_from_file(const char *config_path);

/* Create a new engine from a YAML config string. Returns NULL on failure. */
RouteFlowEngine *routeflow_engine_create_from_string(const char *config_yaml);

/* Resolve a domain to an interface name.
 * Returns a newly allocated string that must be freed with routeflow_free_string.
 * Returns NULL on error. */
char *routeflow_resolve(const RouteFlowEngine *engine, const char *domain);

/* Resolve a domain and return the matched rule description.
 * Returns NULL if no rule matched (default was used) or on error.
 * Must be freed with routeflow_free_string. */
char *routeflow_resolve_rule(const RouteFlowEngine *engine, const char *domain);

/* Get the number of rules loaded in the engine. */
size_t routeflow_rule_count(const RouteFlowEngine *engine);

/* Get the default interface name.
 * Must be freed with routeflow_free_string. */
char *routeflow_default_interface(const RouteFlowEngine *engine);

/* Free a string returned by any routeflow_* function. */
void routeflow_free_string(char *s);

/* Destroy a RouteFlow engine and free its memory. */
void routeflow_engine_destroy(RouteFlowEngine *engine);

#endif /* ROUTEFLOW_CORE_H */
