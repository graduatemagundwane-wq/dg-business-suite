enum DeviceRole {
  owner,
  employee,
}

class RegisteredDevice {
  final String id;
  final String name;
  final DeviceRole role;
  final int? employeeId;
  final DateTime registeredAt;
  final DateTime? lastSyncAt;

  const RegisteredDevice({
    required this.id,
    required this.name,
    required this.role,
    this.employeeId,
    required this.registeredAt,
    this.lastSyncAt,
  });

  RegisteredDevice copyWith({
    DateTime? lastSyncAt,
  }) {
    return RegisteredDevice(
      id: id,
      name: name,
      role: role,
      employeeId: employeeId,
      registeredAt: registeredAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}

class DeviceRegistrationResult {
  final bool success;
  final String message;
  final RegisteredDevice? device;

  const DeviceRegistrationResult({
    required this.success,
    required this.message,
    this.device,
  });
}

class DeviceService {
  static const int defaultEmployeeDeviceLimit = 5;

  static final DeviceService instance = DeviceService._internal();

  factory DeviceService() => instance;

  DeviceService._internal();

  final List<RegisteredDevice> _devices = [];

  List<RegisteredDevice> get registeredDevices => List.unmodifiable(_devices);

  RegisteredDevice? get ownerDevice {
    for (final device in _devices) {
      if (device.role == DeviceRole.owner) return device;
    }

    return null;
  }

  List<RegisteredDevice> get employeeDevices {
    return _devices
        .where((device) => device.role == DeviceRole.employee)
        .toList();
  }

  DeviceRegistrationResult registerOwnerDevice(String deviceName) {
    if (ownerDevice != null) {
      return const DeviceRegistrationResult(
        success: false,
        message: 'Owner device is already registered.',
      );
    }

    return _registerDevice(deviceName: deviceName, role: DeviceRole.owner);
  }

  DeviceRegistrationResult registerEmployeeDevice({
    required String deviceName,
    required int employeeId,
  }) {
    if (employeeDevices.length >= defaultEmployeeDeviceLimit) {
      return const DeviceRegistrationResult(
        success: false,
        message: 'Employee device limit reached.',
      );
    }

    return _registerDevice(
      deviceName: deviceName,
      role: DeviceRole.employee,
      employeeId: employeeId,
    );
  }

  bool removeDevice(String deviceId) {
    final before = _devices.length;
    _devices.removeWhere((device) => device.id == deviceId);
    return _devices.length != before;
  }

  void recordDeviceSync(String deviceId) {
    for (var index = 0; index < _devices.length; index++) {
      final device = _devices[index];
      if (device.id == deviceId) {
        _devices[index] = device.copyWith(lastSyncAt: DateTime.now());
        return;
      }
    }
  }

  DeviceRegistrationResult _registerDevice({
    required String deviceName,
    required DeviceRole role,
    int? employeeId,
  }) {
    final device = RegisteredDevice(
      id: 'DG-DEVICE-${DateTime.now().millisecondsSinceEpoch}',
      name: deviceName,
      role: role,
      employeeId: employeeId,
      registeredAt: DateTime.now(),
    );

    _devices.add(device);

    return DeviceRegistrationResult(
      success: true,
      message: 'Device registered successfully.',
      device: device,
    );
  }
}

extension DeviceRoleLabel on DeviceRole {
  String get label {
    switch (this) {
      case DeviceRole.owner:
        return 'Owner Device';
      case DeviceRole.employee:
        return 'Employee Device';
    }
  }
}
