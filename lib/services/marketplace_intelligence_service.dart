class MarketplaceIntelligenceSettings {
  final bool anonymousContributionEnabled;
  final bool shareSellingPrices;
  final bool shareProductPopularity;
  final bool shareDemand;
  final bool shareInventoryAvailability;

  const MarketplaceIntelligenceSettings({
    this.anonymousContributionEnabled = true,
    this.shareSellingPrices = true,
    this.shareProductPopularity = true,
    this.shareDemand = true,
    this.shareInventoryAvailability = true,
  });
}

class MarketplaceIntelligenceService {
  static final MarketplaceIntelligenceService instance =
      MarketplaceIntelligenceService._internal();

  factory MarketplaceIntelligenceService() => instance;

  MarketplaceIntelligenceService._internal();

  MarketplaceIntelligenceSettings _settings =
      const MarketplaceIntelligenceSettings();

  MarketplaceIntelligenceSettings get settings => _settings;

  void updateSettings(MarketplaceIntelligenceSettings settings) {
    _settings = settings;
  }

  Map<String, Object> buildAnonymousPayloadSummary() {
    return {
      'anonymous': true,
      'selling_prices': _settings.shareSellingPrices,
      'product_popularity': _settings.shareProductPopularity,
      'demand': _settings.shareDemand,
      'inventory_availability': _settings.shareInventoryAvailability,
      'shop_identity_exposed': false,
    };
  }
}
