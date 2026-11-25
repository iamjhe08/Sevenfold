# Sevenfold changes

## Build 20261126.0644

- Sign-in screen: language and Anisette servers are now reachable from the top-right (globe + gear) even while signed out, so a wrong language or an unreachable server can't strand you on the login page.
- Fixed the Sign in button doing nothing after a sign-in sheet was dismissed without completing.
- Sign-in: the field you're typing in now stays above the keyboard on its own (no manual scrolling).
- Schedule and Welcome text now say signing happens at the scheduled time even while the iPhone is locked, matching the iOS 18 fix.

## Build 20261126.0102

- When an anisette server reports an error, the log now shows the server's own message instead of "incomplete headers".

## Build 20261126.0028

- Tested and removed: signing in with this iPhone's own sign-in data. Apple refuses the sign-in ("This action cannot be completed"), so a device-only backup isn't possible; anisette always comes from the servers. Anyone who had the test switch on is put back on the servers automatically.

## Build 20261126.0018

- Tested and reverted: falling back to this iPhone's own AuthKit data when every anisette server fails. Apple answered "no developer team" (it doesn't accept the iPhone's own data for a session signed in through a server), which only hid the real problem. With no server answering, signing now fails with a clear message: "No anisette server answered. Check your connection, or add a working server in Settings › Anisette servers."

## Build 20261125.0803

- Fixed: Apple can drop an iPhone from the Apple ID's device list (seen with the 11 Pro), and Sevenfold only registered the phone when you signed in, so it stayed missing from Registered iPhones and its next signing could fail. Every signing run now checks (at most every 10 minutes) that this iPhone is still on the list and registers it again if not. Logged as "device · this iPhone was missing … registering it again".

## Build 20261125.0749

- New: when App IDs free up. Under the App ID meter, "+3 free on Thu ›"; tap the meter for a list of dates and how many free up each day (dates only: Apple doesn't say which app an App ID belonged to).
- New: Sign when plugged in (Settings › Schedule › Conditions, on by default). Connecting a charger signs any app that expires within your threshold, at most once every 6 hours, following the Wi-Fi setting. Does nothing if no app is close to expiring.
- Removed: "Only while charging" (scheduled runs always run on time now; an old setting is ignored).
- New: certificate expiry reminder. Notifications 14, 3 and 1 day before this iPhone's certificate expires (10:00); tapping opens Certificates. In the last 14 days Certificates shows "Renew and sign all apps", which revokes the old certificate and signs every app with a new one. If the certificate was shared, you're reminded to share the new one.
- Changed: Anisette servers list folds into one row (the server in use, its status and the server count). Tap to show all servers, reorder, add or reset; the choice is remembered.
- Fixed: translations that put values in a different order could show them in the wrong places; such strings now need positional markers or fall back to English.

## Build 20261124.1242

- Fixed: installing an update didn't restart the background service on some jailbreaks (seen on Dopamine), so the old service kept running and newer service fixes never took effect. The installer now also ends the old service, and launchd starts the new one immediately. The service logs "Background service started (installed …)" when it starts, so you can confirm the update is live.

## Build 20261124.1226

- Fixed (real cause of "waits for unlock" on iOS 18): the signing timer only counted time the phone was awake, so when the phone slept through the planned time, the scheduled wake arrived while the timer still thought the run was minutes away; the phone went back to sleep and the run only happened when the screen next turned on. Now:
  - a second timer follows the wall clock, so it is due the moment the phone wakes after the planned time;
  - the background service listens for system wake and runs immediately if the planned time has passed;
  - it holds the phone awake from the start of a scheduled run until the app finishes (released at the end, with the usual time limit).
  New log lines: "Wall-clock timer reached the planned time", "System woke and the planned run is due".

## Build 20261124.1207

- Fixed: scheduled signing on newer iOS (seen on iOS 18) waiting for unlock instead of signing while locked. iOS refuses to start Sevenfold from scratch while the phone is locked, but resuming it when it's already in memory works. The background service now keeps Sevenfold quietly loaded (suspended, no battery assertion) after you unlock, lock, or the screen turns off, when a run is due within 36 hours. At run time it resumes the loaded app as before. If iOS has removed it from memory, the old behaviour (sign at next unlock) still applies. Logged in Background service activity as "Keeping Sevenfold ready for the next run".

## Build 20261123.1220

- Changed: package Section is now "Applications" (Havoc rejected "Utilities"). No app changes.

## Build 20261123.1204

- Changed: Sileo description replaced with the final wording (tagline, Features, Requirements). No app changes.

## Build 20261123.1150

- Changed: package description in Sileo rewritten (short tagline, a features list, requirements). No app changes.

## Build 20261123.1144

- New: swipe an app left on the Apps screen to reveal a red Delete button, like Mail and Notes (right in Arabic). Tapping it, or swiping all the way, asks the same "Delete …?" confirmation as the hold menu, so a quick swipe never deletes by accident. Unavailable while signing is running. Holding an app still opens Open / Delete.

## Build 20261123.1139

- New: first-run guide, three pages before the first sign-in: Welcome (Sevenfold logo), Free Apple ID limits (7 days, 3 apps, 10 App IDs), Signs on its own (schedule + separate Apple ID tip). Swipe or Continue; Skip goes straight to sign-in; the last button opens sign-in in the same sheet. Shown once. Reopen any time from Settings › Support › How Sevenfold works (last button says Done). All 9 languages; pages flow right to left in Arabic.
- New: iPad layout. On a full-screen iPad a sidebar (Apps, Certificates, History, Settings) replaces the tab bar, and every screen keeps a centred reading column (~680 pt) instead of stretching. In Split View / Slide Over (narrow) it falls back to the tab bar. iPhone unchanged.

## Build 20261123.1124

- Changed: the success pop-up after signing says "Valid for 7 days" instead of "6 days, 23 hrs left" (a fresh profile is a few minutes short of 7 days). Same in the pop-up preview in Notifications settings.

## Build 20261123.1123

- Removed: "Allow network access (China iPhones)" in Settings › Diagnostics. Sevenfold already allows itself WLAN & Cellular Data every time it opens, and the sign-in screen fixes it automatically if it can't connect.

## Build 20261123.1115

- Changed: in Certificates › Registered iPhones, the iPhone you're viewing from is always listed first.
- Cleanup: removed the last names inherited from ReProvision. Settings keys are now Sevenfold's own (sfAutoSign, sfSignInLowPower, sfExpiryThresholdDays, sfWakeForRuns, sfAccount, sfTeamID…), as are internal function names, the Home Screen shortcut ID, a notification ID and the sign-in notice. Source folders renamed: Shared/Engine, Shared/Apps, Shared/Account.
- Removed: the inherited rule that adopted a certificate named "AltStore" and the Extender ("EE-") app-group prefix. Sevenfold only uses its own certificate or one it can prove it holds the key for (e.g. a shared one).
- Note: because the saved sign-in moved to new keys, you sign in once after installing this build. Automatic signing, the expiry threshold and Low Power Mode go back to their defaults (on, 2 days, off); the schedule and everything else is kept.

## Build 20261123.1110

- Changed: the email on the Apps card has its own full-width line under the title and App ID meter. Always one line; the font shrinks to fit the address length (15 pt for short ones), never cut off.
- Changed: certificate Serial is one line beside its label, monospaced, and its font shrinks to fit the length. Eye button still hides it.
- New: press and hold the Serial row to copy the full serial (works while hidden). Light haptic, the row lifts, and "Serial copied" shows for 1.5 s.

## Build 20261123.1055

- New: 9 languages: English, 简体中文, Español, Português, Русский, Bahasa Indonesia, 日本語, हिन्दी, العربية. Pick one with the globe button next to + on the Apps screen, or Settings › Language. "Auto (System Language)" follows iOS. The app redraws right away, no restart needed.
- New: Arabic flips the whole layout right to left (navigation, lists, meter, progress bars).
- Changed: the email on the Apps card is smaller and stays on one line.
- Changed: the globe button is blue.
- Changed: certificate Serial shows the full number, with an eye button to hide it.
- Removed: the Certificates section in Settings. Certificates, sharing and revoking all live in the Certificates tab.

## Build 20261123.1038

- New: App ID meter on the Apps card ("4/10 App IDs"): free-account App IDs still active this week (each lasts 7 days). Amber at 8, red at 10; hidden for paid accounts. Refreshed when the Apps screen opens (at most every 5 minutes) and after each run.
- New: apps are signed up to 3 at a time. Starts are 0.5 s apart; the certificate lookup is shared (never two at once, so no duplicate certificates); ldid and installs still run one app at a time. If Apple answers HTTP 429/503 the run drops to one app at a time and that app is retried once. Settings switch "Sign apps at the same time" (on by default). The card reads "Signing 3 apps at once · 1 done", the button "Stop after these apps".
- Fixed: certificate "Expires" was cut off. It now shows the date with "in 12 months" underneath; the serial has its own row.
- Fixed: removing an app's old profile could match a different app whose bundle ID starts the same way (e.g. an app and its extension). It now matches the exact App ID.

## Build 20261123.0026 (rewrite step 5: sign-in · rewrite finished)

- Rewrote Apple sign-in as SFGrandSlam (replaces SFLoginImpl): same requests, headers, identity (iloader 2.4.2 values, akd user agent, X-Xcode-Version) and retries; written as a chain of steps instead of blocking waits, and the SRP memory is now freed after each sign-in.
- Rewrote SFAuthentication (anisette, two-factor session, follow-up sign-in after the code).
- Sign-in steps now appear in Diagnostics › App activity ("sign-in · init answered …", "two-factor code needed", "signed in"). No passwords, codes or tokens are logged.
- Removed the iOS 9 AuthKit fallback (unused on iOS 15+), the old AuthKit header and the old SRP helper (replaced with SFAuthKit.h and SFSRPLayout.m).
- Rewrite complete: no code from the original project remains. NOTICE now lists only the third-party components (ldid, libplist, SSZipArchive/minizip, SAMKeychain, GZIP, OpenSSL, Apple headers).

## Build 20261123.0011

- Fixed: a scheduled run could sign (and reinstall) an app you had uninstalled while Sevenfold was running in the background. Each run now looks every app up again right before it starts and skips removed ones ("skipped … · no longer installed").
- Fixed: the list of apps no longer includes apps whose folder is gone.
- Notifications get a new ID every time (a reused ID let iOS replace an older one silently) and are delivered right away instead of after a 1-second timer. Diagnostics now also log whether iOS actually delivered each one.

## Build 20261122.2350 (rewrite steps 4 and 6)

- Step 4: rewrote SFAppleServices (Apple's developer servers). Same requests, headers and retries as before; now one request path for both the older "actions" calls and the v1 API.
- Step 6: rewrote the background service (sevenfoldd): schedule, hardware wake, opening Sevenfold in the background, keeping it awake while signing. Same settings, times and stored plan, so the next run stays as planned.
- Step 6: split the app's startup. AppDelegate now only handles launch, background refresh and opening files/links; the new SFServiceLink handles the connection to the background service.
- Rewrote SFResources (saved sign-in and preferences; same keychain and setting names) and SFBackgroundSigningManager.
- Removed unused code: old time formatting helpers, an unused 2FA fallback call, unused settings.

## Build 20261122.2339

- Fixed: right after signing, an app could show "Expired · sign now" for a moment. Reinstalling moves the app to a new folder, and the list was still reading the old one. It now looks up the app's current location, and keeps showing the last known time left while iOS finishes the install.

## Build 20261122.2326 (rewrite step 3: certificates and profiles)

- Rewrote SFProvisioning from scratch: team, certificate, App ID and profile are now four clear steps, with Diagnostics lines for each ("certificate · using …", "App ID · updating …").
- The certificate choice is unchanged: the shared certificate is found by its key, and a certificate whose key lives on the other iPhone is never revoked. Keychain item names are unchanged, so the current certificate keeps working.
- New certificates use a SHA-256 request (subject "Sevenfold", PH).
- Fixed: a newly created app group was left blank in the app's entitlements; it now gets its real ID.
- Fixed: revoking when this iPhone had no certificate never answered; it now finishes.
- Rewrote SFAccountChecker; removed the unused SFAppID.

## Build 20261122.2317

- Fixed: installing an .ipa with extensions (like Henge) stopped at 30%. After an extension finished signing, the step that moves on to the main app lost its own data and stopped quietly. It now signs the extensions one at a time and then the main app.
- Fixed: false "ldid still busy after 90 s" warnings in Diagnostics after signing had already finished.
- Diagnostics now also log "extensions done, now <app>" and any extension failure.

## Build 20261122.2212 (version 1.0.0) – ldid diagnostics

- The ipa test showed Apple's part finishing and the stall inside ldid while signing a nested
  extension (HengeJITHelper.appex). ldid now runs on its own thread, logs "ldid started",
  "ldid finished · N files · X s" or the exact error, and a 90-second watchdog reports the file
  ldid was on instead of hanging. ldid's string-type errors are now caught too.

## Build 20261122.2205 (version 1.0.0) – fix: installing an .ipa stuck at 30%

- Cause: for an app Sevenfold hadn't signed before, creating its App ID first asks Apple for
  the team list; if that request failed, the old profile code stopped without reporting back,
  so the run waited forever at 30%. It now reports the error (`SFProvisioning.mm`).
- Safety net: if Apple hasn't finished an app's App ID/profile within 2 minutes, that app
  fails with a clear message instead of hanging (`SFBackend.m`).
- Each signing stage now writes to Diagnostics › App activity ("signing · …").

## Build 20261122.2153 (version 1.0.0) – rewrite step 2 of 6: signing

- Rewritten from scratch: `SFApplicationSigning` (pipeline), `SFBackend` (signing an unpacked
  app, packing), `SFSigning` (certificate identity + ldid), `SFErrors`.
- Same steps and progress points (10/30/50/60/90/100), same installers (InstallCoordination on
  iOS 26+, LaunchServices before), same ".TEAMID" bundle-ID suffix. The original bundle ID is
  now kept under `SFOriginalBundleIdentifier`.
- Fixes along the way: nested extensions and Watch apps are signed one after another; failures
  writing the profile or Info.plist now report an error instead of stalling; errors thrown
  inside ldid are caught and shown; the Apple intermediate certificate is chosen by checking
  which one issued your certificate.

## Build 20261122.2146 (version 1.0.0) – "all signed" card

- After Sign all (or a single app) finishes with no failures, the Apps card turns green with
  a check, "All N apps signed" and "Just now · took X s · good for 7 days"; rows say "Signed
  just now". A line counts down 6 seconds, then the card fades back to the usual one (also
  when you leave the screen).

## Build 20261122.2131 (version 1.0.0) – rewrite step 1 of 6: app list

- Rewritten from scratch: `SFApplication`, `SFApplicationDatabase`, `SFIpaBundleApplication`
  (Shared/AppDatabase). Same behaviour: lists installed user apps signed by your team (iOS's
  recorded team ID, profile as backup), reads the expiry from embedded.mobileprovision,
  icons via UIKit, and reads an .ipa's name, version and icon straight from the archive.

## Build 20261122.2122 (version 1.0.0) – own names throughout

- Every class, file and constant now uses Sevenfold's own `SF` prefix (the engine, the
  background service, the app database and sign-in code were renamed). Log messages, error
  domains, temporary folder names and the certificate request details say Sevenfold.
- Removed the one-time import of another tool's signing key, and its keychain group
  entitlement; Sevenfold uses only its own key (`com.t4mag0.sevenfold`).
- File headers name the project Sevenfold. The original authors' copyright lines stay, as
  the AGPL-3.0 license requires; NOTICE says so.

## Build 20261122.2118 (version 1.0.0) – sign from the app page, hold menu

- App page: Sign now stays on the page. A progress card shows "Signing the app" with cycling
  dots, a percentage and a progress bar (amber outline); the button reads "Signing…". When it
  finishes the card turns green ("Signed just now · Took 5.4 s") and Expires in refreshes;
  on failure it turns red with the reason and Retry. Going back keeps it signing (the row
  shows it). The page also follows a Sign all run that includes the app.
- Apps list: hold an app for a menu with Open (launches it) and Delete (red). Delete asks
  first ("Delete <app>?" · Cancel / Yes, delete), then uninstalls it and the row slides out.
  Delete is disabled while signing.

## Build 20261122.2054 (version 1.0.0) – profile and revoke polish

- Revoke sheet: no "sign all apps right after" option; a revoked certificate leaves the
  Certificates list at once (and stays off it even if Apple still returns it for a moment).
- Settings › Apple ID card: photo without a border; the eye sits at the right of the name
  line and "Edit profile" is its own row (pencil, amber) above Sign out, so the email gets
  the full width at 13 pt and wraps instead of being cut.
- Edit profile: photo without a border; "Apple ID" label with the full address on its own
  line under it, eye on the right.

## Build 20261122.2041 (version 1.0.0) – profile, revoke sheet, cleaner list

- Settings › Apple ID: new card with a round profile photo (or initials), display name, email
  and iPhone model; Team ID removed. An eye button hides the email everywhere in Sevenfold
  (shown as ************). Tap the card for Edit profile: choose a photo from Photos or Files
  (center-cropped to a circle), remove it, set a name. Stored on this iPhone only
  (`Application Support/Sevenfold/profile.jpg`, `sfProfileName`, `sfHideEmail`). `SFProfile.m`.
- Revoke: new confirmation sheet (both Settings › Certificates and the Certificates tab) that
  names the certificate, the apps that stop opening, other iPhones that use it, plus a "Sign
  all apps right after revoking" switch; errors show in the sheet with "Try again".
- Fixed: "Revoke this iPhone's certificate" in Settings did nothing. The "Checking
  certificates…" alert could swallow the confirmation that followed it; it's now a spinner on
  the row.
- Apps list: no bundle ID, just icon, name and time left. While signing, the app being signed
  reads "Signing the app" with dots that cycle . .. ... (none) every half second.

## Build 20261122.1405 (version 1.0.0) – sign in place

- "Sign all apps now" no longer opens a separate signing screen. Signing happens on the Apps
  list: the app being signed gets an amber highlight, its own progress bar, step and %;
  waiting apps are dimmed ("Next", "#2"…); finished apps show "Signed just now" and their new
  time left; failed apps show the reason and a Retry button (tap the row for the full error,
  Retry or Copy error). The top card only says "Signing in progress · 2 of 4 apps · about
  15 s left" (no second progress bar) and its button becomes "Stop after this app". After a
  successful run the card goes straight back to "All apps are signed" with the Apple ID; only
  when something failed does the result ("3 signed · 1 failed") stay for 10 minutes.
- Signing from an app's detail screen goes back to the list to show progress there; signing
  after revoking a certificate switches to the Apps tab. Installing a new .ipa still uses the
  separate progress screen (the app isn't in the list yet).
- Time left is rounded to the nearest hour, so a freshly signed app shows "7 days" / "left"
  instead of "6 days" / "23 hrs left"; it counts down by the hour after that.

## Build 20261122.1342 (version 1.0.0) – new pop-up, Live Activity removed

- Live Activity removed (iOS never started the widget extension for a jailbreak-installed app):
  `widget/`, `SFLiveActivity`, the Swift toolchain step and the "While signing" settings are gone.
- Redesigned in-app pop-up (`SFPopup.m`), shown on all iPhones while Sevenfold is open:
  - Dynamic Island: black pill springs down from under the island and sits below the status
    bar, so the island and overlays such as TrollSpeed stay visible; pulls back under the
    island when it closes.
  - Other iPhones: frosted card with a "SEVENFOLD · now" header slides down from the top.
  - Signed app's icon with a green (success) / red (failure) / amber (nothing to do) badge that
    pops in; amber border and glow; ring and check draw themselves (island); amber-to-gold
    countdown line; 4 s (7 s on failure); Retry button on failures re-signs the failed apps;
    tap or swipe up to close; success/error haptic.
  - Settings › Notifications › Preview pop-up alternates between a success and a failure.

## Build 20261122.1324 (version 1.0.0)

- Live Activity diagnostics (1317 registered the extension but showed only a gray outline):
  the extension writes `widget.log` (start, configuration, each view it draws); 8 s after
  "Preview Live Activity" the app copies those lines and the newest `SevenfoldWidget` crash
  report summary into Diagnostics › App activity.
- In-app pop-up only on iPhones without a Dynamic Island, or when the Live Activity is off;
  on island iPhones its settings section is hidden while the Live Activity is on.

## Build 20261122.1317 (version 1.0.0) – Live Activity

- Fix (after 1311 showed only a gray outline): the extension now has the same jailbreak
  permissions as the app (platform-application, no-container), app and extension share one
  Swift module name for the activity data, and the preview reports if iOS hasn't registered
  the extension.

- **Live Activity while signing.** Dynamic Island: compact view shows the Sevenfold "7" with a
  progress ring on the left and the percentage on the right, with an amber outline (green when
  done, red when failed). Long-press/expanded view: app being signed, "2 of 5 apps", percentage
  and a straight progress bar. Lock screen: the same as a banner (iPhones without an island get
  this only). The result stays 4 s (8 s on failure), then disappears.
- Settings › Notifications › **While signing**: "Live Activity" switch and "Preview Live Activity"
  (a 15-second pretend run).
- iOS only allows a Live Activity to start while the app is open, so runs that start while the
  iPhone is locked (scheduled runs at night) don't show one; their notification still arrives.
- Code: `widget/` (SwiftUI widget extension + Swift bridge, built by `widget/build-widget.sh`),
  `iOS/Sevenfold/SFLiveActivity.m` (calls the bridge at runtime; app still builds without Swift),
  `NSSupportsLiveActivities` in Info.plist, extension packaged at `Sevenfold.app/PlugIns/`.
  `tools/setup-wsl.sh` now downloads the Swift 5.8 toolchain.

## Build 20261122.1252 (version 1.0.0)

Fixes that were first patched into build 20261122.1000's compiled app (builds .1155–.1240), now in the source:

- **No more re-signing every 10–20 minutes.** iOS Background App Refresh no longer starts a
  signing run each time it wakes the app. It only signs as a safety net, when an app would
  otherwise expire within a day (e.g. after missed scheduled runs). (`iOS/AppDelegate.m`)
- **Scheduled runs with the screen off.** The background service wakes the phone 3 s *after*
  the scheduled time instead of 10 s before, so the timer is already due when the phone wakes.
  (`Shared/Daemon/SFDaemonListener.m`)
- **Certificates named "Sevenfold".** New certificates are sent to Apple as
  "Sevenfold · <model>" without a legacy prefix; older prefixed "Sevenfold · …"
  certificates are also recognised as Sevenfold's. (`SFProvisioning.mm`, `SFDevice.m`)
- **Revoking shows success.** Apple answers a successful revoke with HTTP 204 and no body;
  this is now treated as success instead of "unreadable Developer Services response".
  (`SFAppleServices.m`)
- **Revoke for shared certificates.** A certificate this iPhone uses now has both
  "Share with another iPhone" and "Revoke". After revoking the certificate this iPhone signs
  with, Sevenfold offers "Sign all now". (`SFCertificatesViewController.m`)

New in this build:

- **Settings › Certificates › Revoke this iPhone's certificate**, using the same confirmation.
- **"Used by" names the iPhone you shared with** (e.g. "iPhone 15 Pro Max (shared)") on the
  iPhone that shared the certificate, using the Apple ID's registered iPhones.
- **No "No valid PKCS12 certificate" after a shared certificate is revoked.** A certificate
  whose public key doesn't match the private key stored on this iPhone is skipped, so a new
  certificate is created instead of pairing a mismatched key and certificate.

Not done yet: Live Activity / Dynamic Island while signing (needs a Swift toolchain in the
build tools; see README).
