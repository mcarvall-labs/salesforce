/**
 * @description Raised by the AXF-13 identity primitives when inputs are missing or a
 * uniqueness/equivalence invariant is violated. Messages are safe to surface: they never
 * carry financial data or a raw provider payload.
 */
public class AXF_CLS_IdentityException extends Exception {
}
