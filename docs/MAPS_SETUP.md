# Maps setup (G10)

Two different Google keys, never in the repository, never in this chat:

| Key | Used by | Lives in |
|---|---|---|
| **Server key** | `mapsRoute` (road distance and time) | Firebase secret `MAPS_SERVER_KEY` |
| **Android key** | the trip map on the phone | `android/local.properties` as `MAPS_API_KEY=...` (file is not committed) or the environment variable `MAPS_API_KEY` at build time |

With no key the app still runs: the trip map shows a calm "Map not available" note and the fare uses the built-in city table.

## 1. Google Cloud (owner)

1. Cloud Console > the same project as Firebase > Billing is already on (Blaze). Set a **budget alert** first (see docs/BLAZE_GO_LIVE.md, step 2).
2. APIs & Services > Library > enable **Routes API** and **Maps SDK for Android**. Enable nothing else (no Geocoding, no Places) so a stolen key cannot use them.
3. Credentials > Create key twice.

## 2. Restrict the keys (important)

**Server key** (for the function): Application restrictions: **None** (Cloud Functions has no fixed address). API restrictions: **Routes API only**. It sits in a Firebase secret, so only the deployed function can read it.

**Android key**: Application restrictions: **Android apps**, add package `com.example.transport_app` and the SHA-1 of each signing key (debug, upload, and Play App Signing). Get them with:

```powershell
cd android
./gradlew signingReport
```

API restrictions: **Maps SDK for Android only**.

Verify: from a browser, calling a Routes URL with the Android key must answer "API key not valid for this API / referrer"; this is the proof that a leaked Android key is useless for anything else.

## 3. Put the keys in

```powershell
firebase functions:secrets:set MAPS_SERVER_KEY      # type the key when asked
```

For the phone build add one line to `android/local.properties` (the file is ignored by git): `MAPS_API_KEY=` and your Android key.

## 4. Switch on

Deploy functions (docs/BLAZE_GO_LIVE.md), then Admin > Features > **Maps and road distance**. Test: post a load Delhi to Jaipur: the distance should change to the road figure (about 280 km) a second after you stop typing. Switch off = back to the city table at once.

## 5. Cost watch

- Each new city pair costs one Routes request. The answer is kept 30 days in `route_cache` (rounded to about 1 km), so a busy route is paid once a month.
- Limits in `config/mapsLimits`: `perUserPerDay` (default 20) and `totalPerDay` (default 2000). When the total is reached the function refuses and the app falls back to the city table; nothing breaks.
- Set a TTL policy on the field `expireAt` for the collections `route_cache` and `maps_usage` (Console > Firestore > TTL) so they clean themselves.
- Watch: Cloud Console > APIs > Routes API > Metrics, and the budget alert. A normal pilot day is a few dozen requests.
- Maps SDK for Android (the map picture) has a free monthly allowance for the mobile map load; check the current pricing page before switching on for many users.
- The Android key is visible inside the app package (that is normal); the restriction to package + SHA is what protects it.
