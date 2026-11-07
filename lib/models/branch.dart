import 'package:equatable/equatable.dart';

/// Maps to the `branches` table in Supabase.
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
      id: json['id']?.toString() ?? '',
      name: (json['name'] ?? json['title'])?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      geofenceRadiusMeters: (json['geofence_radius_meters'] ??
                  json['geofenceRadiusMeters'] as num?)
              ?.toDouble() ??
          1000.0,
      wifiSsid: (json['wifi_ssid'] ?? json['wifiSsid'])?.toString() ?? '',
      wifiBssid: (json['wifi_bssid'] ?? json['wifiBssid'])?.toString() ?? '',
      nightCollinsBranchId:
          (json['collins_venue_id'] ?? json['nightCollinsBranchId'])
                  ?.toString() ??
              '',
      nightCollinsApiKey:
          (json['night_collins_api_key'] ?? json['nightCollinsApiKey'])
                  ?.toString() ??
              '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'geofence_radius_meters': geofenceRadiusMeters,
      'wifi_ssid': wifiSsid,
      'wifi_bssid': wifiBssid,
      'collins_venue_id': nightCollinsBranchId,
      'night_collins_api_key': nightCollinsApiKey,
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
