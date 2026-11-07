import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps the authenticated area of the app and listens for real-time
/// changes to the current staff member's `profiles` row.
///
/// When an admin approves a device change request they set `device_id`
/// to NULL in the database. This widget detects that event and immediately
/// signs the user out, routing them back to `/login` with an explanatory
/// message.
class SessionDeviceGuard extends StatefulWidget {
  final Widget child;
  const SessionDeviceGuard({super.key, required this.child});

  @override
  State<SessionDeviceGuard> createState() => _SessionDeviceGuardState();
}

class _SessionDeviceGuardState extends State<SessionDeviceGuard> {
  RealtimeChannel? _profileChannel;

  @override
  void initState() {
    super.initState();
    _listenToDeviceInvalidation();
  }

  void _listenToDeviceInvalidation() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _profileChannel = Supabase.instance.client
        .channel('public:profiles:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: user.id,
          ),
          callback: (payload) async {
            final newRecord = payload.newRecord;
            // If device_id was set to NULL by admin approval, force sign-out.
            if (newRecord['device_id'] == null) {
              await Supabase.instance.client.auth.signOut();
              if (mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/login', (route) => false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 6),
                    content: Text(
                      'Device approval granted. '
                      'Please log in on your new device.',
                    ),
                  ),
                );
              }
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_profileChannel != null) {
      Supabase.instance.client.removeChannel(_profileChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
