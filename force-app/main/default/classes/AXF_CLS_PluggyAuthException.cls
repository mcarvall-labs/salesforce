/**
 * @description Raised when authenticating to the Pluggy API fails. Ported from the legacy
 * develop baseline and regressed for AXF-11: message is sanitized, never echoes the
 * response body or credentials.
 */
public class AXF_CLS_PluggyAuthException extends AXF_CLS_PluggyIntegrationException {
}
