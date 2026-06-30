enum AutomatedReportChannel {
  whatsapp,
  email,
  telegram,
  sms,
}

class ReportAutomationSettings {
  final bool dailyReportEnabled;
  final bool weeklyReportEnabled;
  final bool monthlyReportEnabled;
  final bool yearlyReportEnabled;
  final String dailyReportTime;
  final String weeklyReportDay;
  final int monthlyReportDate;
  final List<AutomatedReportChannel> channels;

  const ReportAutomationSettings({
    this.dailyReportEnabled = true,
    this.weeklyReportEnabled = true,
    this.monthlyReportEnabled = true,
    this.yearlyReportEnabled = true,
    this.dailyReportTime = '18:00',
    this.weeklyReportDay = 'Monday',
    this.monthlyReportDate = 1,
    this.channels = const [AutomatedReportChannel.whatsapp],
  });

  ReportAutomationSettings copyWith({
    bool? dailyReportEnabled,
    bool? weeklyReportEnabled,
    bool? monthlyReportEnabled,
    bool? yearlyReportEnabled,
    String? dailyReportTime,
    String? weeklyReportDay,
    int? monthlyReportDate,
    List<AutomatedReportChannel>? channels,
  }) {
    return ReportAutomationSettings(
      dailyReportEnabled: dailyReportEnabled ?? this.dailyReportEnabled,
      weeklyReportEnabled: weeklyReportEnabled ?? this.weeklyReportEnabled,
      monthlyReportEnabled: monthlyReportEnabled ?? this.monthlyReportEnabled,
      yearlyReportEnabled: yearlyReportEnabled ?? this.yearlyReportEnabled,
      dailyReportTime: dailyReportTime ?? this.dailyReportTime,
      weeklyReportDay: weeklyReportDay ?? this.weeklyReportDay,
      monthlyReportDate: monthlyReportDate ?? this.monthlyReportDate,
      channels: channels ?? this.channels,
    );
  }
}

class ReportAutomationService {
  static final ReportAutomationService instance =
      ReportAutomationService._internal();

  factory ReportAutomationService() => instance;

  ReportAutomationService._internal();

  ReportAutomationSettings _settings = const ReportAutomationSettings();

  ReportAutomationSettings get settings => _settings;

  void updateSettings(ReportAutomationSettings settings) {
    _settings = settings;
  }
}

extension AutomatedReportChannelLabel on AutomatedReportChannel {
  String get label {
    switch (this) {
      case AutomatedReportChannel.whatsapp:
        return 'WhatsApp';
      case AutomatedReportChannel.email:
        return 'Email';
      case AutomatedReportChannel.telegram:
        return 'Telegram';
      case AutomatedReportChannel.sms:
        return 'SMS';
    }
  }
}
