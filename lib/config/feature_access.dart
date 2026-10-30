/// Centralized allowlists for features that are being piloted with a
/// specific test user before a wider rollout, rather than gated by role.
///
/// The License & Permit Application entry point embeds the same public
/// `/apply` form used on the web admin panel
/// (https://lacra-admin.onrender.com/apply) inside the Farm Mapping App,
/// without affecting farm data collection for any other user. For now it
/// is restricted to a single test account (Deltrick) rather than an entire
/// role, since existing roles (INSPECTOR/ADMIN) are shared by people who
/// should not yet see this feature.
class FeatureAccess {
  /// Emails (lower-cased) allowed to see the License & Permit Application
  /// entry point on the dashboard. Add more addresses here once the pilot
  /// expands beyond the single test user.
  static const List<String> licenseApplyTestEmails = ['dteah1040@gmail.com'];

  static bool canAccessLicenseApply(String? email) {
    if (email == null || email.isEmpty) return false;
    return licenseApplyTestEmails.contains(email.trim().toLowerCase());
  }
}
