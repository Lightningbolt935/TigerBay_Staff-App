/// App-wide constants. Nothing here should hardcode business/geofencing
/// data — that must always come from the Branch/StaffRolesPermissions
/// records fetched from the backend.
class AppConstants {
  AppConstants._();

  static const String appName = 'TigerBay Staff';

  // Backend base URL — override at build time with --dart-define.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://xxnqlktcbwqhoyezlokv.supabase.co/rest/v1',
  );

  static const String nightCollinsBaseUrl = String.fromEnvironment(
    'NIGHT_COLLINS_BASE_URL',
    defaultValue: 'https://api.nightcollins.example.com/v1',
  );

  // ---- Supabase configuration ----
  // Default values are the live project credentials.
  // Override at build time:
  //   flutter run --dart-define=SUPABASE_URL=https://... \
  //               --dart-define=SUPABASE_ANON_KEY=eyJ...
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xxnqlktcbwqhoyezlokv.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh4bnFsa3RjYndxaG95ZXpsb2t2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE5MTQ5MzYsImV4cCI6MjA5NzQ5MDkzNn0.5BsuhfWfEy-iZSNiJPGKk_QC3eHScWfSe2yhdcMSqMA',
  );

  // ---- OTP configuration ----
  /// Seconds the staff member must wait before requesting a new OTP.
  static const int otpCountdownSeconds = 60;

  // ---- Permission string constants ----
  // These must match the permission column names in the Supabase
  // `staff_roles_permissions` table and the `p_required_permission`
  // parameter accepted by the `check_staff_permission` RPC.
  static const String permCanOverrideTables = 'can_override_tables';
  static const String permCanAlterBooking = 'can_alter_booking';
  static const String permCanIssuePoints = 'can_issue_points';
  static const String permCanRedeemVouchers = 'can_redeem_vouchers';
  static const String permCanViewAnalytics = 'can_view_analytics';

  // Secure storage keys
  static const String secureKeyPinHash = 'staff_pin_hash';
  static const String secureKeyAuthToken = 'staff_auth_token';

  /// Persisted [StaffMember] JSON for warm-start session restore.
  static const String secureKeyStaffJson = 'staff_member_json';

  // Transaction types
  static const String txnIssuePoints = 'ISSUE_POINTS';
  static const String txnRedeemVoucher = 'REDEEM_VOUCHER';

  // Shift statuses
  static const String shiftActive = 'ACTIVE';
  static const String shiftCompleted = 'COMPLETED';
  static const String shiftFlagged = 'FLAGGED';

  // Table statuses
  static const String tableAvailable = 'Available';
  static const String tableOccupied = 'Occupied';
  static const String tableUnavailable = 'Unavailable';

  // Leave request — type values (must match DB CHECK constraint)
  static const String leaveTypeSick = 'sick';
  static const String leaveTypeCasual = 'casual';
  static const String leaveTypeAnnual = 'annual';
  static const String leaveTypeUnpaid = 'unpaid';

  /// All valid [leaveType] values — used for assertion and UI pickers.
  static const List<String> leaveTypes = [
    leaveTypeSick,
    leaveTypeCasual,
    leaveTypeAnnual,
    leaveTypeUnpaid,
  ];

  // Leave request — status values (must match DB CHECK constraint)
  static const String leaveStatusPending = 'pending';
  static const String leaveStatusApproved = 'approved';
  static const String leaveStatusRejected = 'rejected';
}
