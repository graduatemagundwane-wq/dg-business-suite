import '../auth/activation_service.dart';

enum SubscriptionPlan {
  trial,
  monthly,
  yearly,
  lifetime,
}

enum SubscriptionState {
  trial,
  active,
  expired,
  suspended,
  offlineGrace,
}

class SubscriptionStatus {
  final SubscriptionPlan plan;
  final SubscriptionState state;
  final DateTime? expiresAt;
  final DateTime? renewalAt;
  final int offlineGraceDaysRemaining;

  const SubscriptionStatus({
    required this.plan,
    required this.state,
    this.expiresAt,
    this.renewalAt,
    this.offlineGraceDaysRemaining = 0,
  });

  bool get allowsBusinessAccess {
    return state == SubscriptionState.trial ||
        state == SubscriptionState.active ||
        state == SubscriptionState.offlineGrace ||
        plan == SubscriptionPlan.lifetime;
  }
}

class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._internal();

  factory SubscriptionService() => instance;

  SubscriptionService._internal();

  SubscriptionStatus _status = SubscriptionStatus(
    plan: SubscriptionPlan.trial,
    state: SubscriptionState.trial,
    expiresAt: DateTime.now().add(const Duration(days: 14)),
    renewalAt: DateTime.now().add(const Duration(days: 14)),
    offlineGraceDaysRemaining: 7,
  );

  SubscriptionStatus get currentStatus => _status;

  SubscriptionStatus resolveFromActivation(ActivationStatus activationStatus) {
    final state = switch (activationStatus) {
      ActivationStatus.activated => SubscriptionState.active,
      ActivationStatus.pending => SubscriptionState.trial,
      ActivationStatus.suspended => SubscriptionState.suspended,
      ActivationStatus.expired => SubscriptionState.expired,
      ActivationStatus.offlineGrace => SubscriptionState.offlineGrace,
    };

    _status = SubscriptionStatus(
      plan: _status.plan,
      state: state,
      expiresAt: _status.expiresAt,
      renewalAt: _status.renewalAt,
      offlineGraceDaysRemaining: state == SubscriptionState.offlineGrace ? 7 : 0,
    );

    return _status;
  }

  SubscriptionStatus prepareRenewal(SubscriptionPlan plan) {
    final now = DateTime.now();
    final expiresAt = switch (plan) {
      SubscriptionPlan.trial => now.add(const Duration(days: 14)),
      SubscriptionPlan.monthly => now.add(const Duration(days: 30)),
      SubscriptionPlan.yearly => now.add(const Duration(days: 365)),
      SubscriptionPlan.lifetime => null,
    };

    _status = SubscriptionStatus(
      plan: plan,
      state: SubscriptionState.active,
      expiresAt: expiresAt,
      renewalAt: expiresAt,
      offlineGraceDaysRemaining: 7,
    );

    return _status;
  }
}

extension SubscriptionPlanLabel on SubscriptionPlan {
  String get label {
    switch (this) {
      case SubscriptionPlan.trial:
        return 'Trial';
      case SubscriptionPlan.monthly:
        return 'Monthly';
      case SubscriptionPlan.yearly:
        return 'Yearly';
      case SubscriptionPlan.lifetime:
        return 'Lifetime';
    }
  }
}

extension SubscriptionStateLabel on SubscriptionState {
  String get label {
    switch (this) {
      case SubscriptionState.trial:
        return 'Trial';
      case SubscriptionState.active:
        return 'Active';
      case SubscriptionState.expired:
        return 'Expired';
      case SubscriptionState.suspended:
        return 'Suspended';
      case SubscriptionState.offlineGrace:
        return 'Offline Grace';
    }
  }
}
