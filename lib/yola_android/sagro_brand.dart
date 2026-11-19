/// SAGRO / Infraclean Tech customer-specific Yola Android configuration.
///
/// Keep client details out of generic Yola builds. This module is used only
/// by the dedicated client branch. Never embed a login password or licence.
/// Bind SAGRO_BUSINESS_ID to the existing Yola business registration ID at
/// release time; a missing binding prevents document creation.
class SagroBrand {
  static const displayName = 'SAGRO SUPPLY & SUPPORT';
  static const legalName = 'Infraclean Tech T/A SAGRO';
  static const tradingDescription = 'Feedmix Distributor';
  static const address = '738 Rujeko Phase 4, Glendale, Mazowe';
  static const phone = '0790833331';
  static const logoAsset = 'assets/sagro/sagro_logo.jpg';
  static const existingBusinessId = String.fromEnvironment(
    'SAGRO_BUSINESS_ID',
    defaultValue: '',
  );

  static String get documentAddress =>
      '$legalName\n$tradingDescription\n$address';

  static void requireAuthorisedBusiness(String actualBusinessId) {
    if (existingBusinessId.isEmpty) {
      throw StateError(
        'SAGRO has not been linked to its pre-created Yola business account. '
        'Double Gee Tech must configure the client build first.',
      );
    }
    if (actualBusinessId != existingBusinessId) {
      throw StateError(
        'This SAGRO app is not licensed for the signed-in business.',
      );
    }
  }
}
