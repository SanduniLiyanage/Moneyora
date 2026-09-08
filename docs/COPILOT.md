# Moneyora Copilot — what it is, why it is worth building, and how

An in-app **AI agent** that answers plain-language questions about your own
money by deciding which on-device queries to run, executing them against the
encrypted local database, and reasoning over the results.

This document records why the feature exists, what it is deliberately scoped
to, and how it is built.

---

## 1. The honest assessment

The question this document was written to answer: **is this worth building, or
is it a distraction that risks the project?**

### What makes it worth building

| | |
|---|---|
| **It is the most technically substantial feature in the project** | A tool-using agent loop is real orchestration: deciding what to run, validating what comes back, and bounding how long it may go on. Most LLM integrations are a chat box in front of an API; this is not one. |
| **The hard part is already built and tested** | The agent loop, its termination guarantee, and its handling of malformed model output exist with 24 tests. That is the part that is genuinely difficult and genuinely interesting to talk about. |
| **It costs almost no throwaway work** | Its first three tools wrap the aggregate queries Sprint 4 (Analytics) has to build anyway. Building them for the Copilot builds them for the donut chart. |
| **The data it needs already exists** | `dev_seed.dart` holds ~700 deterministic transactions across 24 months, shaped by category. The agent has something real to reason about today. |
| **The privacy design is a better story than the feature** | An AI feature inside an offline-first, encrypted app sounds like a contradiction. Resolving it — tools run locally, only aggregates leave, an automated test proves it — is a design conversation, not a demo. |

### What makes it risky, and what is done about each

| Risk | Reality | Mitigation |
|---|---|---|
| **It displaces the app's own headline features** | Real, and the most serious risk here. An app with a clever agent and no Money Plan Generator is a worse app than the reverse. | The Copilot never jumps the queue. Sprint 5 (Money Plan) and Sprint 6 (Receipt Scanner) ship on schedule; the Copilot's remaining tools *depend* on them, so the incentive points the right way. |
| **Three of the five planned tools have nothing to wrap** | True today. `get_budget_plan` needs Sprint 5; `get_savings_goal_progress` needs a table that does not exist. | Cut to three tools that real data backs (§3). The other two are deferred, not designed away. |
| **It needs a network, in an offline-first app** | True, and the first thing anyone reviewing the design should push on. | It is an *optional* feature behind a connectivity gate with a designed fallback state. Every core feature still works with the radio off — the Copilot is an enhancement, not a dependency. |
| **A live demo can fail — no signal, dead quota, expired key** | The most likely way this feature lets you down in front of someone. | Keep a recorded 60–90 second demo beside the README. A recording does not depend on someone else's network. The offline state is a designed screen, so a failure still looks deliberate. |
| **The model invents numbers** | Language models do this. | Every number in an answer comes from a tool result, the system instruction forbids guessing, and the tool-use trace is shown to the user so a claim can be checked against its source. |
| **It destabilises the app** | Contained by construction. | One feature module, one route. Nothing in `core/`, `transactions/` or `accounts/` imports it. Deleting the route removes the feature. `check_architecture.sh` enforces the boundary in CI. |
| **"That's just an API wrapper"** | The obvious objection, and a fair one to raise. | The loop is hand-written: iteration cap, model-output validation, tool registry, rejection feedback. The tools execute on this device against SQLCipher. The egress guard test is evidence, not a claim. |

### The verdict

**Build it — scoped to three tools, sequenced behind the analytics queries it
shares with Sprint 4, and demoed from a recording.** The risk is not that the
feature fails; it is that it grows. Scope discipline is the whole defence.

---

## 2. Why this is an agent and not a chatbot

A chatbot produces text. This runs a loop, and the loop takes actions:

```
question ─▶ model ─▶ "call get_spending_by_category(2026-08-01 … 2026-08-31)"
                ▲                          │
                │                          ▼
                │              executed HERE, on the phone,
                │              against the encrypted database
                │                          │
                └──── {Food: 3,420,000} ◀──┘
                       ⋯ repeats until the model can answer
```

The defining property is **tool use toward a goal**. The model chooses *what*
to look up; it never chooses how long to run, never sees a raw row, and never
executes anything itself.

---

## 3. Scope for v1 — three tools, not five

A tool is only honest if it wraps something that exists.

| Tool | Backed by | Status |
|---|---|---|
| `get_spending_by_category` | `transactions` + `categories`, seeded | **In v1** |
| `get_income_for_period` | `transactions` where `type = 'income'` | **In v1** |
| `compare_periods` | the same aggregate, run twice | **In v1** |
| `get_budget_plan` | Money Plan Generator — Sprint 5 | Deferred |
| `get_savings_goal_progress` | a `savings_goal` table that does not exist | Deferred |

**The flagship query changes accordingly.** "Can I afford Rs. 50,000 this
month?" (FR-COP-032) needs the plan and the goal, so it moves behind Sprint 5.
The v1 flagship is FR-COP-031:

> **"Where did my budget slip in August?"**

It needs two or three tool calls — this period, the period before, the deltas —
and a piece of reasoning over the result. It is a genuine multi-step agent
demonstration, and the seed data already contains the answer: Car climbs ~8% a
month, Gifts spikes every April and December. The agent should find those.

This is recorded in `SPEC_ERRATA.md` rather than by editing the Copilot SRS.

---

## 4. The privacy design

The centrepiece. Moneyora's promise is that financial data stays on the phone,
and the Copilot keeps it.

| Concern | How the design answers it |
|---|---|
| Raw transactions must not leave the device | Tools execute locally. Only computed aggregates — "Food, August, 34,200" — are sent. Never a row, an id, a merchant, or a note. |
| Prove it, don't claim it | `egress_guard_test.dart` builds a real outbound payload and asserts no raw-row field appears in it. It is a privacy regression test, not a formality. |
| Must work offline | The Copilot is optional and gated on `connectivity_plus`, with a designed fallback screen. Core features never touch it. |
| No secrets in source | The API key lives only in `flutter_secure_storage`. It is never in a Dart constant, an asset, or a committed `.env`. |
| No silent uploads | A network call happens only when a person types a question and presses ask. Nothing runs in the background. |

**In one sentence:** *"The agent's tools execute on-device against an
AES-256 encrypted store; only aggregates ever reach the model, behind a
connectivity gate — so the AI feature never breaks the app's privacy
guarantee, and a test proves it."*

---

## 5. Architecture

One feature module. No architectural exceptions, no changes to existing
features.

```
lib/features/copilot/
├── domain/                        pure Dart — no Flutter, no http, no SQL
│   ├── entities/                  AgentTool · ToolCall · ToolResult
│   │                              LlmStep · CopilotAnswer
│   ├── repositories/              LlmRepository        (abstract, vendor-free)
│   │                              SpendingByCategoryReader  (a narrow port)
│   └── usecases/
│       ├── run_copilot_query.dart THE AGENT LOOP
│       └── tools/                 CopilotTool + one class per tool
├── data/
│   ├── datasources/               GeminiRemoteDataSource — the ONLY network code
│   ├── models/                    llm_dtos — the egress choke point
│   └── repositories/              LlmRepositoryImpl — exceptions → Left(Failure)
└── presentation/
    ├── providers/                 Riverpod AsyncNotifier
    └── pages/                     the ask screen
```

Three properties this layout buys, each enforced rather than intended:

- **The domain knows no vendor.** Swapping Gemini for Groq or Anthropic is a
  new file in `data/datasources/` and one line in `injection.dart`.
- **The domain knows no network.** `check_architecture.sh` fails the build if
  `http` appears above `data/`.
- **Adding a tool changes no existing code.** Tools are registered as a list
  and indexed by their own descriptor name, so the name the model is told and
  the name the loop looks up cannot drift apart.

### Two deliberate departures from `SDD_Copilot.md`

1. **`CopilotTool.execute` returns `Either<Failure, ToolResult>`** instead of
   throwing. Arguments come from a language model, so malformed input is
   ordinary rather than exceptional. This keeps rejection on the normal path
   and keeps `try`/`catch` out of the domain, per repository convention.

2. **`LlmRepository.reason` takes `List<ToolExchange>`, not `List<ToolResult>`.**
   A function-calling API records a conversation: the model's own request has
   to appear in the transcript before the response to it, or the provider is
   being told about a reply to something never asked. The pair also lets the
   model tell its second call from its first, which two same-named results
   cannot.

3. **A rejected tool call is reported back to the model**, not silently
   dropped. A request that vanishes leaves the model asking for the same
   impossible thing until its turns run out — five round trips to arrive
   nowhere. Telling it *"no such tool"* or *"that date is not real"* is what
   lets the loop recover. The rejection carries only the tool name and the
   reason, both of which the model itself produced, so no financial data is in
   it. Rejected calls are **not** added to the user-visible trace: the trace
   says what ran, never what was attempted.

---

## 6. Build sequence

Each step is one session, ends green on `flutter analyze`, `flutter test` and
`check_architecture.sh`, and is one reviewed commit on a `feat/…` branch.

### ✅ Step 1 — Domain entities and the first tool *(done)*
`AgentTool`, `ToolCall`, `ToolResult`, `LlmStep`, `CopilotAnswer`, the
`LlmRepository` contract, `CopilotTool`, and `GetSpendingByCategoryTool` with
31 tests covering the aggregate, the failure passthrough, and ten kinds of
malformed model output.

### ✅ Step 2 — The agent loop *(done)*
`RunCopilotQuery` with 24 tests: the single-tool path, the result reaching the
model on the next turn, multi-tool turns, the offline gate, failure
passthrough, invented tool names, rejected arguments, and termination at
exactly *N* turns.

### ✅ Step 3 — The analytics query the app needs anyway *(done)*
`GetSpendingByCategory` as a real Sprint 4 use case — `CategoryTotal`,
`DateRange`, the repository contract, the aggregate query, the repository impl
and the DI wiring — plus 33 tests.

Two traps the query had to get right, both errata: a transfer writes **two**
rows, so a total that forgets E-02 counts the same movement twice in opposite
directions; and a split's parent row carries the full amount *and* the dominant
category, so counting parents and parts together double-counts the transaction
(E-04). The query reads unsplit expenses `UNION ALL` the split parts.

`SpendingByCategoryReader` moved from the Copilot's domain to
[`lib/core/ports/`](../lib/core/ports/spending_by_category_reader.dart), and
`AnalyticsRepositoryImpl` implements it directly. No adapter, no second query:
the feature's own callers get ids and colours for the chart, and everything
outside the feature gets names and amounts only — which is the shape that may
be sent onward, so the ids are dropped at the port rather than by whoever
happens to call it.

`get_spending_by_category_tool_over_database_test.dart` assembles the whole
chain the app assembles and runs the Copilot's tool against a seeded database.
The single-tool path now works end to end, minus the model.

### ✅ Step 4 — The model, wired *(done)*
`GeminiDtos` (the request builder and response parser),
`GeminiRemoteDataSource` (the only `http` in the application),
`SecureLlmApiKeyStore`, `LlmRepositoryImpl`, `ConnectivityNetworkInfo`, the DI
wiring, and 44 tests including the egress guard.

Four decisions worth naming:

- **The key travels in the `x-goog-api-key` header, not `?key=`.** URLs are
  logged by proxies, crash reporters and `flutter run` itself; headers are not.
- **The key is read per call and never held in a field**, so it is not resident
  in memory — or in a heap dump — for the life of the app.
- **A 429 keeps its status code** through the datasource so the repository can
  raise `QuotaFailure` rather than a generic `ServerFailure`. Waiting fixes a
  spent quota and fixes nothing else, so it is the one status whose advice
  differs.
- **A reply carrying both text and a function call is treated as a call.** A
  model thinking aloud on its way to a tool would otherwise end the loop one
  step early, with its musing presented as the answer.

The API key still has no way *in*: entering it is a screen, so it lands with
Step 5.

**Done when:** the egress guard is green and a scripted Gemini reply — text,
function call, safety block, 429, unparseable body — is handled in each case.
*Met.*

### ✅ Step 5 — The screen *(built; needs a real key to prove)*
`CopilotNotifier`, the ask screen, the loading state, the answer with its tool
trace, the offline fallback, the `/copilot` route, and 11 widget tests.

**The API key is entered on the Copilot screen itself, not in Settings.** It
belongs to this feature alone: without one the Copilot cannot run, and with one
nothing else behaves differently. Putting it in Settings would leave a stray
field there the day the feature is removed. The field is obscured, and the key
goes straight to `flutter_secure_storage` under `gemini_api_key`.

Three things the screen does deliberately:

- **The tool trace is named in plain language.** The model sees
  `get_spending_by_category`; the user reads "your spending by category". The
  trace is not debug output — it is what lets someone check an answer against
  their own figures.
- **Only what actually ran appears in the trace.** A rejected call is fed back
  to the model but never shown, because a trace listing attempts would claim
  the agent consulted something it never read.
- **The offline state is a designed screen**, not an error page. One optional
  feature is unavailable; the app is not broken, and the screen says so.

**Done when:** *"How much did I spend on food in August?"* is answered on the
emulator against seeded data. **The code is finished; this is now a manual
step — it needs a real API key and a running device.**

### Step 6 — The second and third tools
`get_income_for_period`, then `compare_periods`.

**Done when:** *"Where did my budget slip in August?"* triggers two or three
tool calls and explains the answer.

### Step 7 — Prove it
Record the 60–90 second demo video. Add the README section linking to it and to
this document.

### Later — after Sprint 5 and Sprint 6
`get_budget_plan`, then `savings_goal` + `get_savings_goal_progress`, then the
affordability query (FR-COP-032). Post-v1: a proactive agent that flags unusual
spending through a local notification — genuinely agentic, and with no chat
interface at all.

---

## 7. The design questions this feature has to answer

Stated plainly, because a design that cannot answer these is not finished.

**What makes it an agent rather than a chatbot?**
It takes actions. The model requests a tool, the app executes it locally
against the database, the result goes back, and it repeats until the model can
answer. The model chooses *what* to look up; it never chooses how long to run,
never sees a raw row, and never executes anything itself.

**How is privacy preserved when a remote model is involved?**
The tools run on-device against the encrypted store, only computed aggregates
leave, the API key lives in secure storage, nothing runs in the background, and
`egress_guard_test.dart` asserts that no raw-row field can reach the wire.

**Why no agent framework?**
LangChain and LangGraph are Python, and either would have put a server between
the phone and the model — which breaks the privacy guarantee that makes this
feature defensible at all. Writing the loop by hand costs perhaps 150 lines and
keeps every byte that leaves the device under this repository's control.

**What is the hardest part of the design?**
Trusting nothing the model returns. Tool names it invented, dates that do not
exist, arguments of the wrong type, a model that never stops asking — every one
has to become a skipped call or a bounded exit rather than a crash or a hang,
and the model has to be *told* it was rejected, or it asks for the same
impossible thing until its turns run out.
