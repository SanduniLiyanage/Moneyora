# Software Requirements Specification — Moneyora Copilot

**Feature:** AI Copilot (privacy-preserving financial agent)
**Parent product:** Moneyora — offline-first personal finance app
**Document status:** Draft v0.1 (feature-level addendum to Moneyora SRS v1.0)
**Requirement ID prefix:** `COP`

> This document specifies **only** the Copilot feature. It extends, and does not
> replace, the approved Moneyora SRS v1.0. Where a global constraint already
> exists in the parent SRS (offline-first, encryption, no secrets in source),
> it is referenced rather than restated.

---

## 1. Introduction

### 1.1 Purpose
The Copilot is an in-app **AI agent** that answers a user's natural-language
questions about their own finances by autonomously selecting and executing
on-device data queries ("tools"), performing calculations, and reasoning over
the results. It is not a chatbot: its defining behaviour is **tool use toward a
goal**, not free-form text generation.

### 1.2 Scope
In scope: question input, an agent reasoning loop, a set of on-device tools that
read the existing Moneyora data layer, multi-step planning queries
(affordability, savings-goal tracking, period comparison), an offline fallback,
and the privacy controls that keep raw financial data on the device.

Out of scope for this version: proactive background alerts (a post-v1
extension), a fully on-device local LLM, voice input, and multi-currency
reasoning beyond what the parent app already provides.

### 1.3 Definitions
- **Agent** — a component that, given a goal, decides and executes a sequence of
  tool calls until it can answer.
- **Tool** — a named, typed operation the agent may invoke; each tool wraps an
  existing Moneyora `domain/usecase` and runs entirely on-device.
- **Aggregate** — a computed summary value (e.g. a category total) as opposed to
  a raw transaction row.
- **LLM** — the remote large-language model used only for reasoning and tool
  selection.

### 1.4 References
- Moneyora SRS v1.0, SDD v1.0, DBD, ERD (`docs/specs/`)
- `CLAUDE.md` — repository non-negotiables
- `SDD_Copilot.md` — the design that satisfies this specification

---

## 2. Overall description

### 2.1 Product perspective
The Copilot is a new **feature module** inside the existing Flutter application
(`lib/features/copilot/`), following the established Clean Architecture layering
and the enforced inward dependency rule. It consumes existing analytics,
accounts, and Money-Plan use cases; it introduces one new network integration
(the LLM), which is the module's only outbound network path.

### 2.2 User characteristics
The primary user is an individual Moneyora user with existing transaction
history who wants plain-language answers and planning help without learning the
app's analytics screens.

### 2.3 Constraints (inherited, non-negotiable)
- **C-1 Offline-first.** Every *core* app feature must work with the radio off.
  The Copilot is an *optional* networked feature and MUST degrade gracefully
  when offline (see FR-COP-014).
- **C-2 Data locality.** No financial data leaves the device without explicit
  user action; raw transaction rows MUST NOT be transmitted (see FR-COP-010).
- **C-3 No secrets in source.** The LLM API key MUST be held in
  `flutter_secure_storage` (see NFR-SEC-002).
- **C-4 Money is integer minor units** (`amount_cents`); all tool inputs and
  outputs dealing with money MUST use integer cents.

### 2.4 Assumptions and dependencies
- The analytics, accounts, and Money Plan use cases exist (or are seeded) and
  return data the tools can wrap.
- A savings-goal concept is available; if not yet present, this feature
  introduces a minimal one (see FR-COP-020 and the SDD data-model delta).
- A remote LLM with function/tool-calling support is reachable when online.

---

## 3. Functional requirements

### 3.1 Input and session
- **FR-COP-001** The system SHALL accept a free-text financial question from the
  user via a dedicated Copilot screen.
- **FR-COP-002** The system SHALL show a distinct loading state while the agent
  is reasoning, and SHALL remain responsive (non-blocking UI).
- **FR-COP-003** The system SHALL display the final answer together with a
  human-readable trace of which tools were used (for transparency and trust).

### 3.2 The agent loop
- **FR-COP-004** The system SHALL implement an iterative agent loop: submit the
  question and the available tool schemas to the LLM; if the LLM requests a tool
  call, execute it on-device, return the result, and repeat until the LLM
  produces a final answer.
- **FR-COP-005** The loop SHALL be bounded by a configurable maximum iteration
  count (default 5); on reaching the limit it SHALL return a best-effort answer
  or a graceful "couldn't complete" message, never loop indefinitely.
- **FR-COP-006** The system SHALL validate every tool call requested by the LLM
  (known tool name, well-typed parameters) before executing it, and SHALL reject
  malformed calls without crashing.

### 3.3 Tools (on-device data access)
- **FR-COP-007** The system SHALL provide a tool to return spending totals by
  category for a given date range.
- **FR-COP-008** The system SHALL provide a tool to return income for a given
  period.
- **FR-COP-009** The system SHALL provide a tool to return the current Money
  Plan (per-category planned amounts and their confidence).
- **FR-COP-020** The system SHALL provide a tool to return savings-goal progress
  (target, saved-so-far, on-track indicator).
- **FR-COP-021** The system SHALL provide a tool to compare two periods and
  return month-over-month deltas by category.
- **FR-COP-022** Every tool SHALL execute entirely on-device against the local
  encrypted database and SHALL return only aggregates, never raw transaction
  rows.

### 3.4 Query capabilities (what the user can ask)
- **FR-COP-030** The system SHALL answer descriptive questions (e.g. "how much
  did I spend on food in August?").
- **FR-COP-031** The system SHALL answer comparison questions (e.g. "where did
  my budget slip in August?") using one or more tool calls.
- **FR-COP-032** The system SHALL answer affordability questions (e.g. "can I
  afford Rs. 50,000 this month?") by planning a multi-step computation across
  income, committed spending, spending-to-date, and savings-goal buffer, and
  SHALL state the reasoning and any trade-off (e.g. remaining buffer, effect on
  the goal).
- **FR-COP-033** The system SHALL answer savings-goal questions (e.g. "am I on
  track for my goal?").

### 3.5 Privacy and egress control
- **FR-COP-010** The system SHALL NOT transmit raw transaction records,
  merchant strings, or receipt data to the LLM. Only user-question text and
  computed aggregates required to answer it may be sent.
- **FR-COP-011** The outbound payload builder SHALL be covered by an automated
  test asserting that no raw-row fields are present (the privacy guard).
- **FR-COP-012** The system SHALL require an explicit user action (asking a
  question) before any network call; it SHALL NOT contact the LLM in the
  background in this version.

### 3.6 Connectivity and failure
- **FR-COP-013** Before any LLM call the system SHALL perform a connectivity
  check (`connectivity_plus`).
- **FR-COP-014** When offline, the system SHALL display a clear fallback message
  and SHALL NOT error; core app features remain unaffected.
- **FR-COP-015** On LLM error, timeout, or quota exhaustion, the system SHALL
  surface a friendly message and return control to the user without crashing,
  propagating failures as `Either<Failure, T>` per repository conventions.

---

## 4. Non-functional requirements

- **NFR-PER-001** A typical descriptive query SHALL return within 6 seconds on a
  mid-range Android device with normal connectivity (tool execution is local;
  latency is dominated by the LLM round-trip).
- **NFR-SEC-002** The LLM API key SHALL be stored only in
  `flutter_secure_storage`; it SHALL NOT appear in source, assets, or a
  committed `.env`.
- **NFR-PRI-003** No raw financial record SHALL leave the device (verifiable by
  the FR-COP-011 test and by network inspection).
- **NFR-REL-004** Copilot failure (network, LLM, quota) SHALL never destabilise
  core app functionality; the feature is isolated behind its module boundary.
- **NFR-USA-005** The answer SHALL be understandable to a non-technical user and
  SHALL avoid raw numbers without context (e.g. include the period and category).
- **NFR-MNT-006** The Copilot SHALL respect the inward-dependency rule
  (`domain/` imports no Flutter, no http, no database); all network code lives in
  `data/datasources/`. Verifiable via `scripts/check_architecture.sh`.
- **NFR-POR-007** Adding a new tool SHALL require no change to the agent loop —
  tools are registered declaratively.

---

## 5. External interface requirements

### 5.1 User interface
A single Copilot screen: a question input, a send action, a loading indicator, a
scrollable answer area, and a visible tool-use trace. Offline state shows the
fallback message in place of the send action.

### 5.2 LLM interface
An HTTPS request to the configured LLM's function-calling endpoint, carrying:
the system instruction, the user question, the tool schemas, and the running
list of tool results. Response: either a tool-call request or a final answer.
The concrete request/response shape is specified in `SDD_Copilot.md §8`.

---

## 6. Traceability
Each requirement above is mapped to a design component and to a test in
`SDD_Copilot.md §11`. Implementing commits SHALL reference the requirement ID
(e.g. `Refs: FR-COP-032`) per the repository's traceability convention.
