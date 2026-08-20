import 'package:equatable/equatable.dart';

/// Maps to the `branches` table.
/// This is the single source of truth for geofencing, Wi-Fi verification,
/// and Night Collins booking-API credentials for a given branch.
/// Nothing about location/network validation should ever be hardcoded
/// in the app — it must always flow from this model.
class Branch extends Equatable {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double geofenceRadiusMeters;
  final String wifiSsid;
  final String wifiBssid;
  final String nightCollinsBranchId;
  final String nightCollinsApiKey;

  const Branch({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.geofenceRadiusMeters,
    required this.wifiSsid,
    required this.wifiBssid,
    required this.nightCollinsBranchId,
    required this.nightCollinsApiKey,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      geofenceRadiusMeters: (json['geofenceRadiusMeters'] as num).toDouble(),
      wifiSsid: json['wifiSsid'] as String,
      wifiBssid: json['wifiBssid'] as String,
      nightCollinsBranchId: json['nightCollinsBranchId'] as String,
      nightCollinsApiKey: json['nightCollinsApiKey'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'geofenceRadiusMeters': geofenceRadiusMeters,
      'wifiSsid': wifiSsid,
      'wifiBssid': wifiBssid,
      'nightCollinsBranchId': nightCollinsBranchId,
      'nightCollinsApiKey': nightCollinsApiKey,
    };
  }

  Branch copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    double? geofenceRadiusMeters,
    String? wifiSsid,
    String? wifiBssid,
    String? nightCollinsBranchId,
    String? nightCollinsApiKey,
  }) {
    return Branch(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      geofenceRadiusMeters: geofenceRadiusMeters ?? this.geofenceRadiusMeters,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      wifiBssid: wifiBssid ?? this.wifiBssid,
      nightCollinsBranchId: nightCollinsBranchId ?? this.nightCollinsBranchId,
      nightCollinsApiKey: nightCollinsApiKey ?? this.nightCollinsApiKey,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        latitude,
        longitude,
        geofenceRadiusMeters,
        wifiSsid,
        wifiBssid,
        nightCollinsBranchId,
        nightCollinsApiKey,
      ];
}
