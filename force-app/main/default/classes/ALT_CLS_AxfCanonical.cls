public inherited sharing class ALT_CLS_AxfCanonical {
  public static String sha256(String value) {
    return EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', Blob.valueOf(value))
      )
      .toLowerCase();
  }

  public static String frame(List<String> components) {
    if (components == null)
      throw new AxfException('INVALID_INPUT');
    Blob result = Blob.valueOf('');
    for (String component : components) {
      if (component == null) {
        throw new AxfException('INVALID_INPUT');
      }
      Blob bytes = Blob.valueOf(component);
      Integer size = bytes.size();
      String lengthHex = toHex(size);
      result = EncodingUtil.convertFromHex(
        EncodingUtil.convertToHex(result) +
          lengthHex +
          EncodingUtil.convertToHex(bytes)
      );
    }
    return EncodingUtil.convertToHex(result);
  }

  public static String entityRef(String householdKey, String entityKey) {
    return sha256(
      frame(new List<String>{ 'entity-ref-v1', householdKey, entityKey })
    );
  }

  public static String scopedHash(List<String> components) {
    return sha256(frame(components));
  }

  private static String toHex(Integer value) {
    String alphabet = '0123456789abcdef';
    String result = '';
    Integer remaining = value;
    do {
      Integer digit = Math.mod(remaining, 16);
      result = alphabet.substring(digit, digit + 1) + result;
      remaining = remaining / 16;
    } while (remaining > 0);
    while (result.length() < 8)
      result = '0' + result;
    return result;
  }

  public class AxfException extends Exception {
  }
}
