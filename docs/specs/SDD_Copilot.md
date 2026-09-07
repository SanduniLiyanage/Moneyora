# Software Design Document — Moneyora Copilot

**Feature:** AI Copilot (privacy-preserving financial agent)
**Parent product:** Moneyora (Flutter · Dart 3 · Riverpod · SQLite/SQLCipher ·
Clean Architecture, feature-first)
**Document status:** Draft v0.1 (satisfies `SRS_Copilot.md`)

> Read `SRS_Copilot.md` first. This document describes **how** the requirements
> are met. It follows Moneyora's existing SDD conventions and the non-negotiables
> in `CLAUDE.md`.

---

## 1. Design goals and principles
1. **Agent, not chatbot** — the core is a tool-using reasoning loop (SRS §3.2).
2. **Privacy by construction** — tools run on-device; only aggregates leave the
   device; egress is guarded by a test (SRS §3.5).
3. **Reuse, don't rebuild** — tools wrap existing `domain/usecases`; the module
   adds orchestration, not business logic.
4. **Architecture-conformant** — obeys the inward-dependency rule; all network
   code confined to `data/datasources/`.
5. **Isolated failure** — a broken Copilot never affects core features.

---

## 2. Architectural overview

The Copilot is one feature module. Dependencies point inward
(`presentation → domain ← data`); `domain/` is pure Dart.

```
lib/features/copilot/
├── domain/
│   ├── entities/
│   │   ├── copilot_query.dart        # the user's question + context window
│   │   ├── agent_tool.dart           # name, description, param schema
│   │   ├── tool_call.dart            # a requested call (name + args)
│   │   ├── tool_result.dart          # aggregate result of a call
│   │   └── copilot_answer.dart       # final answer + tool-use trace
│   ├── repositories/
│   │   └── llm_repository.dart       # abstract: reason(question, tools, history)
│   └── usecases/
│       ├── run_copilot_query.dart    # THE AGENT LOOP  (FR-COP-004/005/006)
│       └── tools/                    # tool implementations (wrap other usecases)
│           ├── get_spending_by_category_tool.dart
│           ├── get_income_for_period_tool.dart
│           ├── get_budget_plan_tool.dart
│           ├── get_savings_goal_progress_tool.dart
│           └── compare_periods_tool.dart
├── data/
│   ├── datasources/
│   │   └── gemini_remote_datasource.dart   # the ONLY network code (http)
│   ├── models/
│   │   └── llm_dtos.dart             # request/response DTOs + parsing
│   └── repositories/
│       └── llm_repository_impl.dart  # maps errors → Left(Failure)
└── presentation/
    ├── providers/
    │   └── copilot_provider.dart     # Riverpod AsyncNotifier
    └── pages/
        └── copilot_page.dart
```

**Dependency note:** the *tools* live in `domain/usecases/tools/` because they
are pure orchestration over other domain use cases and hold no
Flutter/http/SQL. The actual SQL is reached only through the existing data-layer
repositories the wrapped use cases already depend on — so the rule is preserved.

---

## 3. Component design

### 3.1 Entities
- `AgentTool { name, description, JsonSchema parameters }` — declarative
  description handed to the LLM.
- `ToolCall { toolName, Map<String,dynamic> args }` — what the LLM asks for.
- `ToolResult { toolName, Map<String,dynamic> aggregate }` — aggregate only.
- `CopilotAnswer { text, List<ToolCall> trace }`.

### 3.2 `LlmRepository` (abstract, domain)
```
Future<Either<Failure, LlmStep>> reason({
  required String question,
  required List<AgentTool> tools,
  required List<ToolResult> history,
});
// LlmStep = either ToolCall(s) requested, or a FinalAnswer(text)
```
This keeps the domain independent of any specific LLM vendor (SRS NFR-POR-007).

### 3.3 Tools
Each tool exposes: an `AgentTool` descriptor (for the LLM) and an `execute(args)`
that calls an existing use case and returns a `ToolResult`. See §5 for the
contracts.

### 3.4 `RunCopilotQuery` use case — the agent loop
See §4.

### 3.5 Data source & repository impl (data)
`GeminiRemoteDataSource` builds the HTTPS request, calls the endpoint via `http`,
and parses the response into DTOs. `LlmRepositoryImpl` translates transport/parse
errors into `Left(Failure)` (SRS FR-COP-015). This is the only place that
imports `http`.

### 3.6 Presentation
`copilot_provider.dart` is a Riverpod `AsyncNotifier<CopilotAnswer>` that calls
`RunCopilotQuery` and exposes loading/error/data states; `copilot_page.dart`
renders the question box, loading state, answer, tool trace, and the offline
fallback.

---

## 4. The agent loop (core algorithm)

Satisfies FR-COP-004/005/006/013/014.

```
RunCopilotQuery(question):
    if not connectivity.isOnline:                 # FR-COP-013/014
        return Left(OfflineFailure)

    history = []
    for i in 0 .. MAX_ITERATIONS(=5):             # FR-COP-005
        step = llmRepository.reason(question, TOOL_REGISTRY, history)
        if step is Left: return step              # FR-COP-015
        if step is FinalAnswer:
            return Right(CopilotAnswer(step.text, trace))
        for call in step.toolCalls:
            if not isValid(call): continue        # FR-COP-006 (reject malformed)
            result = TOOL_REGISTRY[call.name].execute(call.args)   # on-device
            assert result contains no raw rows     # FR-COP-010/011
            history.append(result); trace.append(call)
    return Right(bestEffortAnswer(history))        # loop cap reached
```

### 4.1 Sequence (affordability query, FR-COP-032)
```
User → CopilotPage: "Can I afford Rs. 50,000 this month?"
CopilotPage → RunCopilotQuery
RunCopilotQuery → LLM: question + tool schemas
LLM → RunCopilotQuery: call get_income_for_period(this_month)
RunCopilotQuery → (on-device) → aggregate income
RunCopilotQuery → LLM: + income
LLM → call get_spending_by_category(this_month)      # spent so far
LLM → call get_savings_goal_progress()               # buffer needed
LLM → FinalAnswer: "Yes, but it leaves Rs. 8,000 buffer and you'd miss
                    your goal by Rs. 12,000 — spread over two months?"
CopilotPage: renders answer + 3-tool trace
```

---

## 5. Tool contracts

| Tool (name) | Wraps | Params | Returns (aggregate only) | Reqs |
|---|---|---|---|---|
| `get_spending_by_category` | analytics use case | `from`, `to` (ISO dates) | `{category: total_cents}` | FR-COP-007 |
| `get_income_for_period` | accounts use case | `month` (YYYY-MM) | `{income_cents}` | FR-COP-008 |
| `get_budget_plan` | Money Plan Generator | — | `{category: {planned_cents, confidence}}` | FR-COP-009 |
| `get_savings_goal_progress` | savings-goal use case | — | `{target_cents, saved_cents, on_track}` | FR-COP-020 |
| `compare_periods` | analytics | `period_a`, `period_b` | `{category: delta_cents}` | FR-COP-021 |

All monetary values are **integer cents** (SRS C-4). No field may contain a
transaction id, merchant string, or note.

---

## 6. Data-model delta (DBD / ERD addendum)

The Copilot needs almost no new persistence. Two small additions:

### 6.1 `savings_goal` (new, if not already present)
| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `name` | TEXT | e.g. "Emergency fund" |
| `target_cents` | INTEGER | integer minor units |
| `target_date` | TEXT (ISO) | nullable |
| `created_at` | TEXT (ISO) | |

Relationship: `savings_goal` may reference an `account` (FK `account_id`,
nullable) — one account can back many goals. Encrypted at rest like every other
table (SQLCipher).

### 6.2 `copilot_message` (optional, for history UX)
| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `role` | TEXT | `user` / `assistant` |
| `text` | TEXT | the question or answer text only — **never** tool payloads |
| `created_at` | TEXT (ISO) | |

> Design decision: no separate ERD file is required for v1 — these two tables are
> folded into the existing schema and recorded here plus in `SPEC_ERRATA.md` if
> they deviate from an approved baseline, consistent with repo practice.

---

## 7. Privacy & security design

- **Egress builder** (`llm_dtos.dart`) is the single choke point for outbound
  data. It accepts only `question` text and `ToolResult.aggregate` maps. A unit
  test (`test/features/copilot/egress_guard_test.dart`) asserts the serialized
  payload contains none of: transaction id, merchant, note, amount at row level
  (FR-COP-011 / NFR-PRI-003).
- **Connectivity gate** before every call (FR-COP-013).
- **Key handling**: API key read from `flutter_secure_storage` at call time;
  never logged, never in source (NFR-SEC-002).
- **Explicit action**: network only on a user question (FR-COP-012).

---

## 8. LLM integration design (Gemini function-calling)

- Endpoint: Gemini `generateContent` with `tools` = function declarations built
  from the `AgentTool` registry.
- Request carries: `system_instruction` (role + privacy rules + "prefer tools
  over guessing"), `contents` (question + prior tool results as function
  responses), `tools` (schemas).
- Response is either `functionCall` parts (→ `ToolCall`s) or a text part
  (→ `FinalAnswer`). Parsing lives in `llm_dtos.dart`.
- Vendor isolation: swapping to Groq/OpenAI/Anthropic means a new
  `*_remote_datasource.dart` only; domain and loop are untouched
  (NFR-POR-007).

---

## 9. Error handling and failure modes

| Failure | Handling | Req |
|---|---|---|
| Offline | `Left(OfflineFailure)` → fallback UI | FR-COP-014 |
| LLM timeout / 5xx | `Left(ServerFailure)` → friendly message | FR-COP-015 |
| Quota exhausted | `Left(QuotaFailure)` → message + suggest later | FR-COP-015 |
| Malformed tool call | skip call, continue loop | FR-COP-006 |
| Loop cap reached | best-effort answer | FR-COP-005 |

All propagate as `Either<Failure, T>`; no `try/catch` above `data/`.

---

## 10. Testing strategy

- **Unit** — each tool: given fake use-case data, returns correct aggregate.
- **Unit** — agent loop: mocked `LlmRepository` scripted to request N tools then
  answer; assert correct tool execution order and final answer.
- **Privacy guard** — egress serializer excludes raw fields (FR-COP-011).
- **Failure paths** — offline, timeout, malformed call.
- **Architecture** — `scripts/check_architecture.sh` stays green (NFR-MNT-006).

---

## 11. Requirement → design → test traceability

| Requirement | Design element | Test |
|---|---|---|
| FR-COP-001..003 | `copilot_page`, `copilot_provider` | widget test |
| FR-COP-004..006 | `RunCopilotQuery` (§4) | loop unit test |
| FR-COP-007..009, 020..022 | tools (§5) | per-tool unit tests |
| FR-COP-030..033 | loop + tools + LLM instruction | scenario tests |
| FR-COP-010..012 | egress builder, connectivity gate (§7) | egress guard test |
| FR-COP-013..015 | connectivity gate, `LlmRepositoryImpl` (§9) | failure-path tests |
| NFR-SEC-002 | secure-storage key access (§7) | manual + code review |
| NFR-MNT-006 | module layout (§2) | `check_architecture.sh` |

---

## 12. Build order (for implementation with Claude Code)
Follow `CLAUDE.md`'s rule — domain before UI:
`entities → LlmRepository (abstract) → one tool + its test → RunCopilotQuery + loop test → GeminiRemoteDataSource + LlmRepositoryImpl → provider → page`.
Ship the single-tool path end-to-end before adding tools 2–5.
