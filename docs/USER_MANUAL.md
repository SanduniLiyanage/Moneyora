# Moneyora — User Manual

Moneyora keeps track of your money on your phone, and only on your phone.
It works with the radio off. Nothing you enter leaves the phone unless you
choose to send it: a backup you save, an export you share, or a question
you ask Moneyora's assistant.

This manual covers the Android beta. It is written for the person using
the app, not for developers; for those, see [`SETUP.md`](SETUP.md).

---

## 1. The first time you open it

Moneyora opens on the **home screen**. It already has:

- one account, **Cash**;
- fifteen expense categories and three income categories, which you can
  rename, recolour or delete.

Your data is stored in an encrypted database. The key is kept in your
phone's secure keychain, so the file is unreadable to anything else on the
phone.

**Getting around.** The home screen shows where your money went this
month (section 6). Under it, **−** records an expense and **+** records
income. Three buttons sit at the top:

- the **filter** button at the top left opens a panel where you choose the
  account and the period the home screen shows;
- **⇄** at the top right starts a transfer between your accounts;
- **⋮** beside it opens the **menu**: Transactions, Reports, Scan receipt,
  Transfer, Budget plans, Recurring, Categories, Accounts, Ask Moneyora,
  and Settings last.

The back arrow, or your phone's back gesture, returns to where you were.

---

## 2. Accounts

Open **⋮** and tap **Accounts**. It opens in place: every account with its
balance, and the **Total balance** across the accounts you have included
in it. The first row, **Add**, has **⇄** for a transfer and **+** for a
new account.

- **+** adds an account: a name (such as *Cash* or *Commercial Bank
  savings*), a type, an opening balance and the date it was true on, a
  currency, and whether it counts towards the total.
- **Tap an account** to change it. **Delete account** works only for an
  account with no transactions; for one with history Moneyora says so, and
  you can **archive** it instead, which hides it without losing anything.
  **Show archived** brings archived accounts back into view.

Moneyora will not archive your last usable account, because you would have
nowhere to record anything.

---

## 3. Recording money

### An expense or income

Tap **−** on the home screen for **New expense**, or **+** for **New
income**. **Transactions** has the same − and + at its bottom corner.

1. Type the amount on the keypad. It adds, subtracts, multiplies and
   divides: 1250 **+** 340 is recorded as 1,590. **=** finishes a sum,
   and **⌫** in the amount bar removes the last digit.
2. If it was not today, tap the date at the top to change it.
3. The icon at the left of the amount is the account. It starts as the
   account chosen in the panel on the left of home (or the first account,
   with All accounts chosen). Tap it to choose another, such as Cash or a
   card.
4. **Add note** if you want to.
5. Tap **CHOOSE CATEGORY**, then the category. That records the entry and
   takes you back. If the category you want does not exist, tap **New** at
   the end of the grid. The new category is created, and the entry is
   recorded in it.

The icon at the top right switches between an expense and an income.
**Cancel** leaves without recording anything.

Beside the note are three small icons:

- **Repeat** (see below);
- the **camera**, to keep a photo of the receipt with the expense. Photos
  are stored encrypted, and only Moneyora can open them;
- the **scanner**, to read a whole receipt instead (section 5).

To change an entry, tap it in the list, change what you need, then tap
CHOOSE CATEGORY and its category (the current one is ringed). To delete
one, tap it and then the bin at the top, or press and hold it in the list
and choose **Delete**. **Undo** appears for a few seconds in case that was
a mistake.

### Something that repeats

On the same screen, tap **Repeat** beside the note, then choose how often
the entry comes round:
rent every month, a subscription, a salary. Moneyora records each one when
it falls due. **Recurring** (in the menu) lists every repeat,
where you can pause, resume or delete one. With **Recurring reminders**
turned on in Settings, you get a notification before each is recorded.

### Moving money between your own accounts

Tap **⇄** at the top of the home screen (or **Transfer** in the menu, or
the transfer button on **Transactions**), choose **From** and **To**, the
amount and the date —
cash drawn from a card at an ATM, for example, is a transfer from the card
to Cash. In the list it is two rows: a red minus on the account the money
left, a green plus on the one it reached. Look at one account and its
Balance and day totals move with it; look at all accounts and the two
cancel. A transfer is not spending: it never counts in a chart or a
budget. Between
two currencies it also asks how much arrived, suggesting a figure from the
exchange rates you keep in Settings; type the amount on your statement if
the bank's differs.

### The list

**Transactions** lists everything newest first, grouped by day with each
day's total. An expense shows a red arrow pointing down and income a green
arrow pointing up, the way each moves your balance; a transfer shows the
two-way arrows. **All**, **Expenses** and **Income** at the top filter the
list. It shows the same period and account as the home screen. **Swipe**
sideways, or use **‹** and **›**, for the period before or after, and tap
the balance to choose another period or account. **Group by category**
shows each category's entries together with their total; **List by date**
goes back. An account opened in the period shows its **Opening balance**
as a row on the day it was opened; change it on the account itself.

---

## 4. Categories

**Categories** (in the menu) lists your categories. Tap one to
rename it, change its icon or colour, or put it under another as a
sub-category. **Add category** (the **+**) makes a new one.

---

## 5. Scanning a receipt

1. Open **Scan receipt** in the menu and choose **Take a photo** or
   **Choose from gallery**. The text is read on your phone; the photo is never uploaded.
2. **Review receipt** shows what was read: the merchant, the total, the
   date, and each item with its amount and a suggested category. Correct
   anything that is wrong. Whatever could not be read is left blank for
   you to type in, never filled with a guess or a zero; a receipt read with
   no items opens as one expense, waiting for its total. **Split** one line into two, **Merge with next** to join
   two, or **Discard** a line that is not a purchase.
   To file the whole receipt under one category instead, turn on **One
   category for the whole receipt** and choose it; the receipt is then
   saved as a single expense.
3. Tap **Confirm**. Each item you keep becomes its own expense, paid from
   the account the receipt names if it names one, with the photo kept
   beside it.

Moneyora learns from your corrections: the next receipt from the same shop
suggests the categories you chose. **Receipt history** (the clock icon on
the scan screen) lists every scan; open one to see its photo, or
**Re-scan** it.

Receipts print in many layouts, and some will read badly. A photo reads
best flat, in good light, with the receipt filling the frame; a slight
tilt is allowed for. Always check the review screen before you confirm.

---

## 6. The home screen and Reports

The home screen is a ring of the period's spending. Around it, each
category you spent on shows its icon and its share of the total. In the
middle, income is in green and spending in red.

- **‹** and **›** beside the period's name step to the period before or
  after. **Swiping** the ring sideways does the same: towards the left for
  the next period, towards the right for the one before.
- **Balance** under the ring is what came in less what went out, plus the
  opening balance of an account opened in the period. Tap it to see the
  transactions behind it.

The **filter** button at the top left chooses what home and Reports show:

- **an account**, or **All accounts**;
- **Day**, **Week**, **Month**, **Year** or **All**;
- **Interval**, for any run of days: on its calendar, swipe between
  months, tap the first day, then the last (it can be in another month),
  and tap **OK**;
- **Choose date**, which moves the period to the day you pick: with
  **Month** chosen, picking 3 March shows March.

The panel closes as you choose, and the screen changes with it.

**Reports** (in the menu) has every chart for the same period and account:

- **Spending by category**: the ring with each category's amount.
- **Income vs expenses**: the two side by side, and what was left.
- **Summary**: average spent a day, your largest category, and the change
  on the period before.
- **Spending over time**: each category's spending as a line.
- **Daily spending**: each day of the month shaded by how much was spent.

---

## 7. The Money Plan

The Money Plan works out a budget from how you have actually spent.

The Money Plan works two ways. Moneyora can **suggest** a plan from how
you have actually spent, once it knows enough about that. Or you can
**build** one yourself, at any time, by typing a budget for each category.

### When there is not enough history yet

Moneyora suggests a plan only from your own spending, never from made-up
examples. It needs at least one whole month with spending in it, and at
least 10 expenses. Until then, **Create Money Plan** tells you what is
missing (for example, that this month's expenses start counting when the
month ends) and offers **Build it yourself**.

### Building a plan yourself

1. Open **Budget plans** in the menu, tap **Create Money Plan**,
   and choose the period under **Plan for**.
2. Tap **Build it yourself** (or **Or build it yourself**, below
   **Generate plan**).
3. Every expense category is listed. Type a budget for each one you want
   to plan, and leave the rest empty: an empty category stays out of the
   plan. The total at the top, and what it comes to a day, follow as you
   type.
4. Remove a category with **×**, or add one with **Add a category**.
5. Tap **Save plan**.

### Having Moneyora suggest a plan

1. Open **Budget plans** and tap **Create Money Plan**.
2. Under **Plan for**, choose a day, week, month, year, a number of days,
   or a date range.
3. Under **Total budget**, choose how the total is decided:
   - **From your spending history**: what your usual spending adds up to;
   - **Set a total**: a figure you choose, shared across categories in
     proportion to your usual spending;
   - **Suggest from income**: your income, less your fixed costs, less the
     savings you want to keep.
4. Tap **Generate plan**.

The plan looks back over the last six months unless you change **Money
Plan looks back** in Settings (from 1 to 24 months).

### Reading the plan

For every category, **Your plan** shows the amount, what that comes to a
day, and how it was reached:

- **Fixed**, **Variable** or **Seasonal**: how steady the category's
  spending has been. A seasonal category (gifts every December, for
  example) is only recognised with 24 months of history.
- **Confidence**: **High**, **Medium** or **Low**, from how much history
  there is and how much it varies. Treat a Low figure as a guess.
- A **rising** or **falling** trend adds to or takes from the figure.

At the end, **Spending patterns** says whether you spend more on weekdays
or at weekends, and at the start or the end of a month. Bills paid on a day
or two a month are left out of it, and it says which.

**Edit amounts** lets you change the suggestion before you save it: change
any figure, remove a category or add one. The total follows what you type,
and the screen shows how far it is from the suggested total.

### Saving a plan

Tap **Save plan**, give it a name, and leave **Track it now** ticked to
start following it. If budget alerts are off, the same box offers **Alert
me near and over each limit**; leave it ticked and Moneyora asks your
phone for permission to send notifications.

### Following a plan

In **Budget plans**, tap the plan marked **Active**. It shows each
category's budget against what you have spent so far, green while there is
room and red once it is over. Tap a category to change its budget; the
others are recalculated so the total stays the same. In a plan of one
category, the total changes with it. **What if…** shows what a change would
do before you make it. Once the plan's period has ended it says **ended**,
and what each category finished at.

When a category goes over, Moneyora offers three ways to answer:

- **Auto-redistribute**: take the overspend from the other categories, in
  proportion to what each has left;
- **Manual adjust**: take it from one category you choose;
- **Carry over**: take it off the same category in your next plan.

With budget alerts on (offered when you save a plan, or in Settings ›
**Budget alerts**), you get a notification when a category reaches 80% of
its budget, telling you roughly how much is left, and another when you use
it up or go over, telling you how far over you are.

### Budget plans

**Budget plans** lists every plan you have kept, the active one first.
Open a plan's menu (**⋮**) to **Activate** it, **Compare with…** another
plan category by category, **Rename…** it or **Delete…** it. The same
**Rename…** and **Delete…** are in the menu of the plan itself.

Deleting a plan removes its budgets. Your transactions stay exactly as
they are. If it was the active plan, nothing is tracked until you activate
another.

---

## 8. Asking Moneyora

**Ask Moneyora** answers questions about your spending, such as *"How much
did I spend on food last month?"* or *"What were my three biggest
categories this month?"*. It sees only how much was spent in each category,
so it cannot tell you an account's balance or your income. It is the one
feature that needs the internet, and it is optional.

It uses Google's Gemini service, with a free API key you get from Google AI
Studio and type in once (**Save key**). The key is kept in the phone's
secure keychain. To correct a mistyped key or use a new one, tap the key
button at the top (**Change API key**) and enter it again.

When you ask a question, Moneyora sends Google the question, today's date
and the totals per category for the dates it needs. It never sends
individual transactions, notes, merchants or photos. Without a key, or
offline, every other part of the app works as normal.

---

## 9. Settings

| Section | What it holds |
|---|---|
| **Appearance** | **Theme**: follow the phone, always light, or always dark. |
| **Currency** | **Base currency** for totals, and the **Exchange rates** used to convert other currencies into it. |
| **Calendar** | **Week starts on**, **Month starts on day** (for a month that runs from payday to payday), **Money Plan looks back**, and your **Savings target** as a percent of income. |
| **Notifications** | **Budget alerts** and **Recurring reminders**, and when reminders come. |
| **Security** | **Set a passcode**, and **Biometric unlock**. |
| **Data** | **Recalculate account balances**, **Back up now**, **Restore from a backup**, **Export transactions**, **Clear all data**. |
| **About** | What stays on the phone, and what the database holds (useful if you ever report a problem). |

### Passcode and biometrics

A passcode is 4 to 6 digits. After five wrong tries Moneyora makes you wait
before trying again, and the wait grows with each further mistake.
**Biometric unlock** lets your fingerprint or face open the app instead,
and the passcode always works as well. If you forget the passcode, there is
no way to recover it: keep a backup.

---

## 10. Backing up, restoring and exporting

### Back up

**Back up now** asks for a password, twice, and then where to save the
file. A backup is a single `.mora` file holding everything: accounts,
transactions, plans, categories and receipt photos. It is encrypted with
your password, so it is safe to keep on Google Drive or send to yourself.

**Without the password the backup cannot be opened, by anyone, including
us.** Write it down somewhere safe.

If you have not backed up for seven days, Moneyora reminds you.

### Restore

**Restore from a backup** opens a `.mora` file and asks for its password.
Restoring **replaces everything on this phone** with what is in the
backup; it does not merge the two. This is also how you move to a new
phone: back up on the old one, install Moneyora on the new one, and restore.

Your passcode is not part of a backup. Set one again on the new phone.

### Export

**Export transactions** saves your transactions as a **Spreadsheet (CSV)**,
for Excel or Google Sheets, or as a **PDF** to read or print. The PDF's
standard fonts cannot show Sinhala or Tamil letters; the CSV keeps every
character.

### Clear all data

**Clear all data** deletes every account, transaction, plan and photo and
starts again from the first-launch state. It cannot be undone, except by
restoring a backup.

---

## 11. Questions

**Does Moneyora need an account or a sign-in?** No. There is no Moneyora
server.

**What happens if I lose my phone?** Your data is encrypted on it. To get
it back on another phone you need a backup file and its password.

**Why does a figure in the plan look wrong?** The plan is only as good as
the history it learns from. A Low confidence label says so. You can change
any category's figure by hand.

**The receipt scanner read something wrong.** Correct it on the review
screen before confirming. Moneyora remembers the categories you choose.

**Which phones does it run on?** Android 8.0 or later. An iPhone version is
not part of this beta.
