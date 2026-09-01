/**
 * @description Raised by Pluggy source discovery (AXF-84) when the request is not allowed,
 * consent is not valid, or an external result is uncertain. Messages are sanitized: no
 * account name/number, no secret, no raw provider payload.
 */
public class AXF_CLS_PluggyDiscoveryException extends Exception {
}
