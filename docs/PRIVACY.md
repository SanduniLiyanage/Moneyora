# Moneyora — Privacy Policy

*Effective 28 September 2026. Applies to the Moneyora app for Android.*

Moneyora is a personal finance app that keeps your data on your phone.
There is no Moneyora account, no Moneyora server, and no advertising or
analytics code in the app. This policy says what the app stores, what can
leave your phone, and when.

## What Moneyora stores, and where

Everything you enter (accounts, transactions, categories, budgets, plans,
settings and receipt photos) is stored **only on your phone**:

- The database is encrypted (AES-256, SQLCipher). Its key is kept in your
  phone's secure keystore.
- Receipt photos you keep are encrypted separately, in the app's private
  storage.
- An optional passcode is stored as a salted hash in the secure keystore,
  never as the digits themselves.

We, the developers, cannot see any of it. Android's automatic app-data
backup to Google Drive is turned off for Moneyora, so a copy does not leave
the phone that way either. Uninstalling the app deletes everything, and so
does **Settings › Clear all data**. To move to a new phone, use the app's
own encrypted backup (below).

## What can leave your phone, and only when you choose

1. **A backup you save.** **Back up now** writes one `.mora` file,
   encrypted with a password you choose, to a place you pick (for example
   your Downloads folder or Google Drive through the phone's save dialog).
   Without the password nobody can open it, including us.
2. **An export you share.** **Export transactions** writes a CSV or PDF
   file of your transactions to a place you pick. These files are **not**
   encrypted, because they are meant to be read by other programs; keep
   them somewhere private.
3. **A question you ask Ask Moneyora (optional).** This is the only feature
   that uses the internet, and it is off until you enter your own Google
   Gemini API key. When you ask a question, Moneyora sends Google:
   - the question you typed; and
   - the total spent in each category for the dates the question needs.

   It never sends individual transactions, notes, merchant names, account
   names or balances, or photos. What Google does with that request is
   governed by Google's own terms for the Gemini API. Your API key is kept
   in the phone's secure keystore.

Nothing else is sent anywhere. The receipt scanner reads text **on the
phone** (Google ML Kit's on-device text recognition); photos are never
uploaded.

## Permissions

| Permission | Why |
|---|---|
| Notifications | Budget alerts at 80% and 100% of a budget, reminders before a recurring entry, and a reminder to back up. Each is off until you turn it on. |
| Run at startup | To put scheduled reminders back after the phone restarts. |
| Biometrics | To unlock the app with your fingerprint or face, if you turn this on. |
| Internet, network state | Only for Ask Moneyora, and to check for a connection before trying. |
| Vibration | For notifications. |

Moneyora does not request your location, contacts, microphone or camera
permission. When you scan a receipt, the phone's own camera app takes the
photo and hands it to Moneyora.

## Children

Moneyora is not directed at children under 13 and does not knowingly
collect anything from anyone, of any age.

## Changes

If this policy changes, the new version will be published at the same
address with a new effective date, and summarised in the app's release
notes.

## Contact

Questions about this policy: **moneyora.app@gmail.com**.
