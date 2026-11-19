/// SAGRO / Infraclean Tech customer-specific Yola Android configuration.
///
/// Keep client details out of generic Yola builds. This module is used only
/// by the dedicated client branch. Never embed a login password or licence.
/// Bind SAGRO_BUSINESS_ID to the existing Yola business registration ID at
/// release time; a missing binding prevents document creation.
class SagroBrand {
  static const displayName = 'SARGO Supply & Support';
  static const legalName = 'SARGO Supply & Support';
  static const tradingDescription = '';
  static const address = 'Plot 9 Sub division 18, Welston, Glen Forest, Harare';
  static const phone = '+44 7419 339101';
  static const logoAsset = 'assets/sagro/sagro_logo.jpg';
  static const existingBusinessId = String.fromEnvironment(
    'SAGRO_BUSINESS_ID',
    defaultValue: '9cdeb31c-0883-4ba0-8d20-50d115011e2c',
  );

  static String get documentAddress =>
      '$legalName\n$address';

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
