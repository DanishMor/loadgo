# Admin web console (F32)

The same code can be built as a web page that shows **only** the admin area.
Nothing is deployed by the build. You do the steps below yourself.

## Build

    flutter build web --release --dart-define=APP_MODE=admin --output=build/web_admin

`APP_MODE=admin` is chosen at build time (`lib/core/app_mode.dart`). The normal
build (`flutter build web --release`) has no admin-only shell.

## What the admin build does

- Signed out: the normal sign-in pages.
- Signed in as an admin (`admins/{uid}` exists): the Admin Panel only (`lib/admin/admin_web_shell.dart`).
- Signed in as anyone else: "This account is not an admin." and a Sign out button. No customer, driver or fleet screen can be opened from the shell.
- The Firestore and Storage rules are still the real gate; the shell only hides screens.

## Host it on its own address (owner step)

1. In the Firebase console (Hosting) add a **second site**, for example `load20-admin`.
2. Add a hosting target and a second entry in `firebase.json`:

        firebase target:apply hosting admin load20-admin

        "hosting": [
          { "target": "main",  "public": "hosting", ... },
          { "target": "admin", "public": "build/web_admin",
            "headers": [ { "source": "**", "headers": [
              { "key": "X-Frame-Options", "value": "DENY" },
              { "key": "Referrer-Policy", "value": "no-referrer" } ] } ],
            "rewrites": [ { "source": "**", "destination": "/index.html" } ] }
        ]

   (This is not in `firebase.json` yet: an unmapped target would stop the
   current deploy. Add it only when the second site exists.)
3. Deploy only that target: `firebase deploy --only hosting:admin` (owner runs it; this project's tools never run deploy).
4. In Authentication > Settings > Authorized domains add the new address.

## Good to know

- Keep the admin address private. Staff should use a fresh browser profile and sign out when done.
- Sign-in uses the same phone code as the app (limits in `OTP_SECURITY.md` apply).
- The page cannot be opened inside another site (X-Frame-Options DENY).
