enum StaffRole {
  concierge('Concierge'),
  staff('Staff'),
  manager('Manager'),
  director('Director');

  final String value;
  const StaffRole(this.value);

  static StaffRole fromString(String? role) {
    if (role == null) return StaffRole.staff;

    switch (role.trim().toLowerCase()) {
      case 'concierge':
        return StaffRole.concierge;
      case 'manager':
        return StaffRole.manager;
      case 'director':
        return StaffRole.director;
      case 'staff':
      default:
        return StaffRole.staff;
    }
  }

  // ── 1. Bookings: All 4 roles can view ─────────────────────────
  bool get canViewBookings => true;

  // ── 2. Redeem Rewards (Scanner / Claim): Staff, Manager, Director
  bool get canRedeemRewards =>
      this == StaffRole.staff ||
      this == StaffRole.manager ||
      this == StaffRole.director;

  // ── 3. Award Strips (Give Points): Manager & Director only ────
  bool get canAwardStrips =>
      this == StaffRole.manager || this == StaffRole.director;

  // ── 4. Complete / Revert Rewards: Manager & Director only ─────
  bool get canCompleteRewards =>
      this == StaffRole.manager || this == StaffRole.director;

  // ── 5. Access Fulfillment Queue Screen: Manager & Director ───
  bool get canAccessFulfillmentScreen =>
      this == StaffRole.manager || this == StaffRole.director;
}
