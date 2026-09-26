import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/network/dio_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'api_providers.g.dart';

/// The generated root client over the main Dio (auth + problem interceptors).
///
/// Features read one of the per-tag clients below and wrap calls in
/// `apiCall` so failures arrive as `ApiException`s:
///
/// ```dart
/// @riverpod
/// Future<List<GroupSummary>> groups(Ref ref) {
///   ref.watch(currentUserIdProvider); // reset on logout / account switch
///   return apiCall(ref.watch(groupsClientProvider).listGroups);
/// }
/// ```
///
/// Public endpoints (no token) use the `public…` providers instead.
@Riverpod(keepAlive: true)
FriendsApi friendsApi(Ref ref) => FriendsApi(ref.watch(dioProvider));

/// The generated root client over the **bare** Dio, for the public endpoints
/// (contract section 12: public calls skip the auth interceptor): health,
/// login, register, refresh, logout and the invite preview.
///
/// They never wait behind a token refresh queued in the auth interceptor:
/// logging out stays fast while a refresh hangs on a slow network. Errors
/// are raw `DioException`s, so always call them through `apiCall`.
@Riverpod(keepAlive: true)
FriendsApi publicApi(Ref ref) => FriendsApi(ref.watch(bareDioProvider));

/// `GET /health` (public).
@Riverpod(keepAlive: true)
HealthClient healthClient(Ref ref) => ref.watch(publicApiProvider).health;

/// The public auth calls: login, register, refresh, logout.
@Riverpod(keepAlive: true)
AuthClient publicAuthClient(Ref ref) => ref.watch(publicApiProvider).auth;

/// The authenticated auth call: logout-all. Use [publicAuthClient] for the
/// others.
@Riverpod(keepAlive: true)
AuthClient authClient(Ref ref) => ref.watch(friendsApiProvider).auth;

/// `/me`: profile, password, account deletion.
@Riverpod(keepAlive: true)
UsersClient usersClient(Ref ref) => ref.watch(friendsApiProvider).users;

/// Groups and members.
@Riverpod(keepAlive: true)
GroupsClient groupsClient(Ref ref) => ref.watch(friendsApiProvider).groups;

/// Invites: create, list, revoke, accept. The preview is public: use
/// [publicInvitesClient].
@Riverpod(keepAlive: true)
InvitesClient invitesClient(Ref ref) => ref.watch(friendsApiProvider).invites;

/// The public invite preview (`GET /invites/{code}`).
@Riverpod(keepAlive: true)
InvitesClient publicInvitesClient(Ref ref) =>
    ref.watch(publicApiProvider).invites;

/// Categories and their custom fields.
@Riverpod(keepAlive: true)
CategoriesClient categoriesClient(Ref ref) =>
    ref.watch(friendsApiProvider).categories;

/// The backlog: activities, their status and interests.
@Riverpod(keepAlive: true)
ActivitiesClient activitiesClient(Ref ref) =>
    ref.watch(friendsApiProvider).activities;

/// The "What should we do?" wheel.
@Riverpod(keepAlive: true)
WheelClient wheelClient(Ref ref) => ref.watch(friendsApiProvider).wheel;

/// Polls inside activities.
@Riverpod(keepAlive: true)
PollsClient pollsClient(Ref ref) => ref.watch(friendsApiProvider).polls;

/// Events and the calendar.
@Riverpod(keepAlive: true)
EventsClient eventsClient(Ref ref) => ref.watch(friendsApiProvider).events;

/// The group availability heatmap (`/me/availability` is on [usersClient]).
@Riverpod(keepAlive: true)
AvailabilityClient availabilityClient(Ref ref) =>
    ref.watch(friendsApiProvider).availability;

/// A group's month or year recap.
@Riverpod(keepAlive: true)
RecapClient recapClient(Ref ref) => ref.watch(friendsApiProvider).recap;

/// A group's feed.
@Riverpod(keepAlive: true)
FeedClient feedClient(Ref ref) => ref.watch(friendsApiProvider).feed;
