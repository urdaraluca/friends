/// Stable machine-readable `code` values of problem responses.
///
/// Every code in contract section 2 is listed here (a test keeps the two in
/// sync). The app branches on these, never on `title` or `detail`.
abstract final class ErrorCodes {
  /// 422: the request's shape or values are invalid; `errors[]` says where.
  static const validationError = 'validation_error';

  /// 401: missing, malformed or revoked access token. The client logs out.
  static const unauthenticated = 'unauthenticated';

  /// 401: the access token has expired. The client refreshes once, retries.
  static const tokenExpired = 'token_expired';

  /// 401: login failed (unknown email, deleted account or wrong password).
  static const invalidCredentials = 'invalid_credentials';

  /// 401: the refresh token is unknown, revoked or expired.
  static const refreshInvalid = 'refresh_invalid';

  /// 401: a rotated refresh token was reused; the whole family is revoked.
  static const refreshReuseDetected = 'refresh_reuse_detected';

  /// 422: the current password is wrong (`/me/password`, `/me/deletion`).
  static const wrongPassword = 'wrong_password';

  /// 422: the new password equals the email address (register,
  /// `/me/password`). Comes without `errors[]`.
  static const weakPassword = 'weak_password';

  /// 403: a member without the needed role or ownership.
  static const forbidden = 'forbidden';

  /// 403: invite-only registration without an invite code.
  static const registrationClosed = 'registration_closed';

  /// 404: missing resource, not a member of its group, or unknown invite.
  static const notFound = 'not_found';

  /// 405: a known path with the wrong method.
  static const methodNotAllowed = 'method_not_allowed';

  /// 409: registering with an email that already exists.
  static const emailTaken = 'email_taken';

  /// 409: a duplicate category name or poll option label.
  static const nameTaken = 'name_taken';

  /// 409: the PUT's `version` doesn't match. The client offers "Reload" only.
  static const versionConflict = 'version_conflict';

  /// 409: the owner must transfer ownership first.
  static const ownerMustTransfer = 'owner_must_transfer';

  /// 409: a vote or new option on a closed poll.
  static const pollClosed = 'poll_closed';

  /// 409: accepting a spin whose result activity was deleted.
  static const resultDeleted = 'result_deleted';

  /// 410: the invite has expired.
  static const inviteExpired = 'invite_expired';

  /// 410: the invite was revoked.
  static const inviteRevoked = 'invite_revoked';

  /// 410: the invite has no uses left.
  static const inviteExhausted = 'invite_exhausted';

  /// 422: an ID in the body doesn't exist in this group.
  static const invalidReference = 'invalid_reference';

  /// 422: a third category level.
  static const categoryDepthExceeded = 'category_depth_exceeded';

  /// 422: a custom-field key clashes with the parent's or a child's.
  static const fieldKeyConflict = 'field_key_conflict';

  /// 422: an existing custom-field key was given a different type.
  static const fieldTypeChange = 'field_type_change';

  /// 422: activity attributes don't match the field definitions.
  static const invalidAttributes = 'invalid_attributes';

  /// 422: the RRULE is outside the allowed subset.
  static const invalidRrule = 'invalid_rrule';

  /// 422: the calendar range is longer than 400 days.
  static const rangeTooLarge = 'range_too_large';

  /// 422: more than one option on a single-choice poll.
  static const tooManyChoices = 'too_many_choices';

  /// 422: a wheel spin with fewer than 2 candidates.
  static const notEnoughCandidates = 'not_enough_candidates';

  /// 422: a count limit (contract section 1.9) would be exceeded.
  static const limitReached = 'limit_reached';

  /// 429: too many requests; comes with `Retry-After`.
  static const rateLimited = 'rate_limited';

  /// 500: an unhandled server error.
  static const internalError = 'internal_error';

  /// Every code from contract section 2.
  static const contractCodes = <String>{
    validationError,
    unauthenticated,
    tokenExpired,
    invalidCredentials,
    refreshInvalid,
    refreshReuseDetected,
    wrongPassword,
    weakPassword,
    forbidden,
    registrationClosed,
    notFound,
    methodNotAllowed,
    emailTaken,
    nameTaken,
    versionConflict,
    ownerMustTransfer,
    pollClosed,
    resultDeleted,
    inviteExpired,
    inviteRevoked,
    inviteExhausted,
    invalidReference,
    categoryDepthExceeded,
    fieldKeyConflict,
    fieldTypeChange,
    invalidAttributes,
    invalidRrule,
    rangeTooLarge,
    tooManyChoices,
    notEnoughCandidates,
    limitReached,
    rateLimited,
    internalError,
  };
}
