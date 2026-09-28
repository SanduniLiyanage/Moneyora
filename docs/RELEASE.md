# Releasing Moneyora

What stands between this repository and an app someone can install. Written
after the Sprint 10 beta-readiness pass, when everything on the code side was
done and everything left was an account, a key, or a wait.

Read [`SETUP.md`](SETUP.md) §7 first for the signing key; this file is the
order to do things in and the things no commit can do for you.

---

## The short version

| Step | Who | How long |
|---|---|---|
| Upload key generated, backed up | you, once | 5 minutes |
| Signed `.aab` built | `flutter build appbundle --release` | 5 minutes |
| Play Console account, identity verified | you | **1–5 days**, Google's pace |
| Closed test, 12 testers, 14 days | you + 12 people | **14 days minimum** |
| Production review | Google | 1–7 days |
| Apple Developer Program | you | 1–2 days, **$99/year** |
| iOS build and upload | needs macOS | see below |

**Nothing in the code is blocking.** Every remaining item is an account, a
payment, a person, or a calendar.

---

## 1. The upload key

Do this once, outside the repository, and never commit the result.

```powershell
keytool -genkey -v -keystore D:\dev\keys\moneyora-upload.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

It asks for a password twice and for a name and organisation; the name can be
your own. Then create `android/key.properties` — git ignores it:

```properties
storeFile=D:/dev/keys/moneyora-upload.jks
storePassword=<the password you chose>
keyAlias=upload
keyPassword=<the same password, unless you chose another>
```

**Back up the `.jks` file and the password somewhere that is not this
machine.** With Play App Signing, Google holds the key that signs what users
actually install, so a lost upload key can be reset through the Play Console —
but that takes days, and it is days you will not want to spend.

Without `key.properties` the release build still succeeds, signed with the
debug key. It installs and runs; the Play Console refuses it. That fallback
exists so CI and a fresh clone keep building, not as a way to ship.

## 2. The bundle

```powershell
flutter build appbundle --release
```

The result is `build/app/outputs/bundle/release/app-release.aab`. Upload
*that*, not an APK: Play has required the bundle format for new apps since
2021, and it is what lets Google build a per-phone download.

To check what a user will actually download, build the split APKs instead —
CI gates each at 80 MB (SRS §2.4, [E-09](SPEC_ERRATA.md)):

```powershell
flutter build apk --release --split-per-abi
```

At the Sprint 10 measurement: 32.1 MB (armeabi-v7a), 39.8 MB (arm64-v8a),
42.3 MB (x86_64). The largest is at half the budget.

## 3. Google Play

1. **Register** at [play.google.com/console](https://play.google.com/console)
   — $25, once, ever. A *personal* account then has to pass identity
   verification: a government ID and an address, checked by a human, over
   days rather than minutes. Start this before you need it.
2. **Create the app.** The listing text, the data-safety answers and the
   asset list are all in [`store/LISTING.md`](store/LISTING.md), written to
   Google's character limits.
3. **Upload the `.aab`** to a closed testing track.
4. **The 14-day rule.** A personal developer account registered after
   November 2023 must run a closed test with **at least 12 testers who stay
   opted in for 14 continuous days** before it may apply for production
   access. The clock does not start until the twelfth tester joins, and it
   restarts if the count drops. This is the single longest item in this
   file, and no amount of code changes it — line up twelve people early.
5. **Apply for production**, then submit. Review is usually days.

### The data-safety form

Answer it from [`PRIVACY.md`](PRIVACY.md), not from memory. The one answer
that is easy to get wrong: the app *does* send data off the phone, but only
the optional AI assistant, only on the user's own key, only when asked, and
only category totals — never transactions. Declare it rather than claiming
the app is entirely offline, which the INTERNET permission would contradict.

## 4. Apple, and the Mac problem

**An iOS release needs macOS.** Xcode builds, signs and uploads iOS apps and
runs on nothing else. This project has no Mac in the loop — which is why
iOS has been compile-only in CI from the start.

Two ways out, in order of cost:

- **A macOS CI runner.** GitHub Actions' `macos-latest` already compiles this
  app on every push. The same runner can archive and upload to App Store
  Connect with an App Store Connect API key in the repository's secrets, no
  Mac of your own required. This is the cheap route and the one this project
  is already half-way along.
- **Borrow or rent a Mac** for a day.

Either way you first need the **Apple Developer Program**: $99 a year, and
its own identity verification. Apple's review is typically 1–3 days and is
stricter than Google's about screenshots matching the app.

The floor is **iOS 15.5**, not the SRS's 14 — ML Kit's text recogniser
requires it ([E-20](SPEC_ERRATA.md)). Say 15.5 in App Store Connect.

## 5. Before you submit, either store

- [ ] Install the **release** build on a real Android phone and open every
      screen. The emulator has never caught a missing runtime permission.
- [ ] Take the screenshots from the release build, not a debug one — the
      debug banner is an automatic rejection.
- [ ] Check the privacy policy is reachable at a public URL. Both stores
      require a link, not a file.
- [ ] Fill in the contact address in [`PRIVACY.md`](PRIVACY.md) and
      [`store/LISTING.md`](store/LISTING.md) — it is published, so use an
      address you are willing to make public.
- [ ] Back up the keystore. Again.

---

## What is deliberately not here

**No crash reporting, no analytics.** Nothing in the app reports back, which
is the promise the privacy policy makes. It also means a crash on a user's
phone is invisible to you: the first weeks of a release are when a beta group
you can actually talk to is worth more than a dashboard.
