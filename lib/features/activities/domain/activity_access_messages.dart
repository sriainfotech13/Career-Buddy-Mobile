/// The message shown when a student-only activities page redirected an
/// employer/recruiter session to its own portal. It is a role problem, not a
/// plan lock, so the UI must NOT offer "View Plans" for it (see
/// `PortalSeparationMiddleware`, `core/portal_access.py`).
const activityRoleMismatchMessage =
    'Activities are not available for this account type. Please use the portal that matches your account.';

/// The upgrade-prompt message for a plan-locked activity (the server's
/// `/activities/?locked=1` redirect).
const activityLockedMessage = 'This activity requires an upgrade to access.';
