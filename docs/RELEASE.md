# Releasing Moneyora

What stands between this repository and an app someone can install. Written
after the Sprint 10 beta-readiness pass, when everything on the code side was
done and everything left was an account, a key, or a wait.

Read [`SETUP.md`](SETUP.md) §7 first for the signing key; this file is the
order to do things in and the things no commit can do for you.

---

## The short version

The owner's choice, 2026-09-29: **free distribution first** — GitHub Releases
and the Samsung Galaxy Store. Google Play ($25, once) and the App Store
($99 a year) stay open for later and are described below.

| Step | Who | How long |
|---|---|---|
| Upload key generated, backed up twice | you, once | 5 minutes |
| Four repository secrets set | you, once | 5 minutes |
| `git tag v1.0.0` and push | you | the workflow takes ~15 minutes |
| Galaxy Store seller account | you | free; a day or so |
| Galaxy Store review | Samsung | several days |
| *Later:* Google Play | you + 12 testers | $25 once; **14 days** of closed testing |
| *Later:* App Store | you | $99/year; needs macOS (or the CI runner) |

**Nothing in the code is blocking.** Every remaining item is a key, an
account, or a wait.

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

**Back up the `.jks` file and the password in two places that are not this
machine.** Outside Google Play there is no second chance: GitHub Releases and
the Galaxy Store install exactly what you sign, so **this key is the app's
identity for good**. Lose it, or its password, and no phone that installed
Moneyora will ever accept an update from you; the only way forward is a new
app under a new name. (Play is kinder — with Play App Signing, Google holds
the key users' phones check, and a lost upload key can be reset, over days.
If you move to Play later, give Play *this* key as the app signing key, so
the installs that came from GitHub and Galaxy keep updating.)

Without `key.properties` the release build still succeeds, signed with the
debug key. It installs and runs; the Play Console refuses it. That fallback
exists so CI and a fresh clone keep building, not as a way to ship.

## 2. GitHub Releases

The workflow in [`.github/workflows/release.yml`](../.github/workflows/release.yml)
builds, signs, checks and publishes. You give it the key once, then tag.

**Once — the four secrets.** From the repository folder, in PowerShell:

```powershell
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("D:\dev\keys\moneyora-upload.jks"))
$b64 | gh secret set UPLOAD_KEYSTORE_BASE64
gh secret set UPLOAD_KEY_ALIAS --body upload
gh secret set UPLOAD_STORE_PASSWORD
gh secret set UPLOAD_KEY_PASSWORD
```

The last two ask for the password and do not echo it, so it never lands in
your shell history. GitHub stores secrets encrypted and never shows them
again, not even to you.

**Each release.**

1. Raise the version in `pubspec.yaml`: `1.0.0+1`, then `1.0.1+2`, and so
   on. The number after the `+` must go up every time, or phones refuse the
   update as a downgrade.
2. Merge that to `main`, then tag it:

   ```powershell
   git switch main; git pull
   git tag v1.0.0
   git push origin v1.0.0
   ```

3. Watch **Actions › Release**. It refuses to publish if the tag and
   `pubspec.yaml` disagree, if a secret is missing, or if the APK came out
   signed with the debug key. When it passes, the release page has
   `moneyora-1.0.0-arm64-v8a.apk`, `…-armeabi-v7a.apk`, `SHA256SUMS.txt`
   and install instructions.

What people see: Android warns about installing from an unknown source the
first time, and there are no automatic updates — they come back to the
release page for a new version.

**How someone who already has Moneyora gets the update.** They download
the new APK from the release page and open it. Android offers **Update**,
not Install, and keeps every transaction, plan and setting, because two
things hold: the new APK is signed with the **same upload key**, and its
build number (after the `+`) is **higher** than the one installed. Break
either and Android refuses ("App not installed"), and the only way past is
to uninstall, which deletes their data unless they made a backup first.
Never uninstall to "fix" an update.

Nothing tells them an update exists. Post the release where your testers
are, with what changed. Someone who wants to be told can add the
repository to [Obtainium](https://github.com/ImranR98/Obtainium), a free
app that watches GitHub Releases and offers each new APK. The Galaxy Store
(§3), and Play later, update installed copies by themselves.

A pull request that edits the workflow runs it as a dry run (no key, no
release; the APKs are kept as a build artefact for three days), so a broken
pipeline shows up on its PR, not on release day.

## 3. Samsung Galaxy Store

A manual upload of the same APK, through Samsung's Seller Portal.

1. Sign up at [seller.samsungapps.com](https://seller.samsungapps.com) with
   a Samsung account. A seller account for free apps costs nothing.
2. **Add new application › Android**, and upload
   `moneyora-<version>-arm64-v8a.apk` from the GitHub release. Add the
   armeabi-v7a one as well if the portal offers a second binary.
3. The listing: the text is in [`store/LISTING.md`](store/LISTING.md),
   category **Finance**; screenshots are in `store/screenshots/`, the
   feature graphic in `store/feature-graphic.png`, and the icon in
   `assets/icons/icon.png` (1024 px; the portal lists the sizes it wants).
4. Privacy policy URL, which the repository being public makes free:
   `https://github.com/SanduniLiyanage/Moneyora/blob/main/docs/PRIVACY.md`.
5. Answer the age-rating questionnaire truthfully — no violence, no
   gambling, no user-to-user contact — and submit. Samsung's review takes
   several days.

**Updates** are a new binary on the same app in the Seller Portal, signed
with the same key and with a higher version number than the last.

## 4. The bundle, for Play later

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

## 5. Google Play, later

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

## 6. Apple, and the Mac problem

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

## 7. Before you publish anywhere

- [ ] Install the APK from the release page on a real Android phone —
      yours, or a friend's Samsung — and open every screen. The emulator
      has never caught a missing runtime permission.
- [x] Screenshots from a release build, not a debug one (the debug banner is
      an automatic rejection): `store/screenshots/`, taken 2026-09-28;
      the home screen and the list retaken from 1.0.1 on 2026-10-06, for
      the Budget plans tile and the arrows.
- [x] The privacy policy at a public URL: the repository is public, so the
      file's GitHub page is one.
- [x] A contact address in [`PRIVACY.md`](PRIVACY.md) and
      [`store/LISTING.md`](store/LISTING.md): moneyora.app@gmail.com.
- [ ] Back up the keystore. Again.

---

## What is deliberately not here

**No crash reporting, no analytics.** Nothing in the app reports back, which
is the promise the privacy policy makes. It also means a crash on a user's
phone is invisible to you: the first weeks of a release are when a beta group
you can actually talk to is worth more than a dashboard.
