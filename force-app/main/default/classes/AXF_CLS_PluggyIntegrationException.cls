/**
 * @description Base exception for the Pluggy credentials & consent capability (AXF-11).
 * Messages carried by subclasses are already sanitized: they name the endpoint, HTTP
 * status and a correlation id, never a secret, token, request body or raw response.
 */
public virtual class AXF_CLS_PluggyIntegrationException extends Exception {
}
