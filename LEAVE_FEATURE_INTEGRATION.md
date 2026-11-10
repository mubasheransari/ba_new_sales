# BA Sales Leave Feature Integration

This update adds BA self-service leave management to the existing Flutter app without changing the existing attendance, sales, complaints, dashboard, Firebase, or login flows.

## Included
- Leave management action card on the Home screen.
- Leave list with All / Pending / Approved / Declined / Cancelled filters.
- Apply for one-day or date-range leave with reason.
- Leave detail and chronological conversation thread.
- Reply to pending leave requests.
- Cancel pending requests or approved requests when cancellation is permitted by the API.
- Bearer token reuse from the existing AuthBloc and the existing Repository HTTP/error handling.

## Backend prerequisite
Run the supplied Oracle HRMS leave setup script first, then publish all six ORDS handlers in module `ba_sales_v2`:
- `POST leave/apply`
- `GET leave/list?filter=all`
- `GET leave/thread/:id`
- `POST leave/message/:id`
- `POST leave/decide/:id` (admin-side; not exposed in the BA app)
- `POST leave/cancel/:id`

The app uses the existing base URL in `lib/Api_config/api_config.dart`:
`http://tapex.mezangrp.com/ords/hrms/ba-sales-v2`

## Important
The provided API handlers allow every non-BA role to list and decide leaves. Keep the admin decision endpoint and APEX admin pages restricted to explicitly authorized administrator accounts; do not treat “non-BA” by itself as sufficient admin authorization.

## Run
1. Extract the ZIP.
2. From the `ords_ba` directory run `flutter pub get`.
3. Run `flutter run` on a test device.
4. Sign in with a BA account, open Home > Manage leave, apply for a future date, then verify the list/thread/reply/cancel flow against the deployed ORDS endpoints.

The project could not be compiled in this environment because the Flutter SDK is not installed here. Compile and test on the development Mac before releasing.


## Build-fix update

The fixed project archive also corrects Dart compilation errors in `lib/Screens/leaves_screen.dart` (bottom-sheet and leave-thread widget structure) and removes the unsupported `alignment` argument from `AnimatedSwitcher` in `lib/Widgets/sales_chart.dart`. Gradle/AGP/Kotlin upgrade notices may still appear as warnings; they were not the compilation errors reported in the supplied build log. The project could not be run through Flutter analysis/build in this environment, so please verify locally with `flutter analyze` and `flutter run`.

## UI update (leaves match complaints)

Leave Management now uses the same design as Complaints:
- Home card: same red gradient, unread-reply badge, dynamic subtitle.
- `leaves_screen.dart`: summary card, pill filters with counts, inbox-style tiles.
- `new_leave_screen.dart` (new): full-screen apply form replacing the bottom sheet.
- `leave_thread_screen.dart` (new): chat-style thread with status banner, bubbles, composer.
- `Widgets/leave_widgets.dart` (new): shared status colours / date helpers.
- `Repository.applyLeave` now returns the new leave id.
