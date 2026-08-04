/**
 * @description       :
 * @author            : Michel Carvalho Lopes
 * @group             : Altice Labs
 * @last modified on  : 08-04-2026
 * @last modified by  : Michel Carvalho Lopes
 * @tested with       :
 * @version           : 1.0
 * @modification log  :
 * Modifications Log
 * Ver   Date         Author                  Modification
 * 1.0   08-04-2026   Michel Carvalho Lopes   Initial Version
 **/
public with sharing class AXF_CLS_StringUtils {
  public static String padStart(
    String value,
    Integer targetLength,
    String padChar
  ) {
    if (String.isBlank(value))
      return value;

    Integer padCount = targetLength - value.length();
    if (padCount <= 0)
      return value;

    return padChar.repeat(padCount) + value;
  }
}
