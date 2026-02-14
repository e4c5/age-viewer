# Apache AGE Visualizer: Clean-Room Requirements

## 1. Purpose and Scope

This document defines the requirements for a new implementation of an Apache AGE graph visualizer, based on behavior analysis of the current `age-viewer` codebase. The goal is to preserve useful capabilities and provide a production-grade architecture using a FastAPI backend and a separate frontend client.

Scope includes:
- Web UI for connecting to PostgreSQL + Apache AGE.
- Cypher query authoring/execution and result visualization.
- Graph metadata exploration.
- Graph initialization from CSV.
- Interactive graph exploration and customization.

## 1.1 System Decomposition

The clean-room implementation must be split into two primary components:

1. Backend Service
- A standalone FastAPI application exposing a REST API.
- Owns database connectivity, query execution, metadata discovery, import orchestration, auth/session controls, and policy enforcement (safe mode, limits, audit).
- Must be deployable independently from the frontend.

2. Frontend Client
- A separate web application consuming the backend REST API.
- Owns editor UX, result rendering, filtering controls, layouts, and user interaction workflows.
- Graph visualization layer should be implemented with D3.js.

Integration contract:
- The frontend must not connect directly to PostgreSQL.
- All data access must pass through backend APIs.
- Backend and frontend should be versioned and released independently, with a documented API compatibility policy.


## 2. Current-System Capability Inventory (Observed)

## 2.1 Backend capabilities
- Session-scoped database connection pool per user session.
- Connect/disconnect/status endpoints:
  - `POST /api/v1/db/connect`
  - `GET /api/v1/db/disconnect`
  - `GET /api/v1/db`
- Metadata endpoint:
  - `POST /api/v1/db/meta` returns graph-wise node/edge label counts and role data.
- Cypher execution endpoint:
  - `POST /api/v1/cypher` with raw SQL string wrapping AGE `cypher(...)` calls from client.
- Graph initialization endpoint:
  - `POST /api/v1/cypher/init` accepts CSV node/edge files, creates graph/labels, inserts data.
- AGE agtype parser integration via custom ANTLR-based parsing.
- AGE/Postgres version-specific metadata SQL templates for PG 11-15 (`backend/sql/*`).

## 2.2 Frontend capabilities
- Connection workflow with connect/disconnect/status frames.
- Command editor with history and keyboard shortcuts:
  - run via `Shift+Enter` or `Ctrl+Enter`
  - browse history via `Ctrl+Up/Down`.
- Multi-frame result workspace (graph frame, table frame, status frames).
- Query result routing:
  - graph-like results -> graph/table tabbed result frame.
  - non-graph/update/error -> table/text style frame.
- Cytoscape graph visualization with multiple layouts.
- Interactive graph features:
  - legend per node/edge label.
  - change label color/size/caption.
  - filter graph/table by property values.
  - edge thickness mapping from numeric property range.
  - right-click node context actions: expand neighborhood, hide, pin/unpin, delete node in DB, add/remove filter.
- Sidebar metadata explorer:
  - node labels, edge labels, properties.
  - click-to-generate query templates.
  - graph switching support.
- Graph creation modal from CSV files.
- Query builder drawer based on keyword transition matrix (`/api/v1/miscellaneous`).
- Theme and display settings persisted in cookies.

## 2.3 Test coverage observed
- Unit tests for agtype parsing and object serialization.
- Integration test for graph initialization with AGE-enabled postgres docker.
- Coverage is limited relative to feature surface.

## 3. Current-System Gaps and Risks (Must Address)

## 3.1 Security
- Raw query submission from client with minimal server validation.
- Session secret hardcoded in source in the current codebase.
- Session config likely incorrect for local dev/proxy (`secure: true` always).
- Node/edge CSV import query construction used string interpolation without robust escaping in the current codebase.
- Database credentials stored in frontend redux state and returned by backend status payload.

## 3.2 Functional issues / broken paths
- Frontend has calls to `GET /api/v1/db/metaChart`, but backend `getMetaChart` implementation is commented out.
- Frontend CSV upload frame targets `/api/v1/feature/uploadCSV`; backend has no such route.
- Metadata chart in status frame depends on `state.metadata.rows`, but metadata state primarily stores `graphs` map.
- Several existing commands (`:play`, `:csv`) are incomplete/partially broken.

## 3.3 Reliability and correctness
- Metadata counts rely on `ANALYZE` tuple estimates (`reltuples`), not exact counts.
- Extensive mutable shared state on frontend (global color/size maps) can leak across frames.
- Inconsistent error handling and user feedback pathways.
- Multiple UI components use direct DOM manipulation patterns that are brittle.

## 3.4 Maintainability
- Legacy React 17 + class/functional mix + duplicated logic.
- Thin API contract; backend behavior tightly coupled to frontend assumptions.
- Many TODOs and commented-out paths in production flow.

## 4. Product Requirements for New Implementation

## 4.1 Functional Requirements
1. Connection Management
- User can connect to PostgreSQL with host/port/db/user/password and optional SSL params.
- User can disconnect and reconnect cleanly.
- UI shows current connection status and selected graph.
- Connection credentials must never be returned to UI after connect.
- Backend architecture is explicitly stateful.
- Session and graph context are maintained server-side for each active user session.
- Horizontal scaling is not a requirement for this implementation.
- Deployment model must be explicitly defined:
  - Web deployment inside same private network/VPC as PostgreSQL.
  - If remote DB access is required, support secure tunnel/proxy patterns.

2. Graph Discovery and Metadata
- System lists available AGE graphs in current database.
- For selected graph, system returns:
  - node labels with counts
  - edge labels with counts
  - discovered property keys per label/type (node/edge)
- System provides a meta-graph view of discovered label-to-label relationship patterns.
- User can switch active graph at any time.

3. Cypher Query Execution
- User can execute Cypher statements from editor.
- System supports read and write commands.
- Result payload supports mixed row shapes (vertex/edge/path/scalars/maps/lists).
- Errors include clear message and structured code fields.
- Query cancellation is required for long-running queries.
- Parameterized execution is required (`cypher + params`) to avoid ad-hoc string interpolation.
- Optional safe/read-only mode must be enforceable server-side, rejecting mutating clauses before DB execution.

4. Result Visualization
- Graph view:
  - use D3.js as the graph rendering foundation.
  - implement a `d3-force` based simulation for node-link layout (or deterministic static layout mode when configured).
  - implement zoom/pan with `d3-zoom`.
  - render with SVG by default; support Canvas rendering mode for large graphs.
  - separate render layers for edges, nodes, labels, and interaction overlays.
  - support incremental enter/update/exit rendering for streaming or paged graph updates.
  - expose a deterministic styling pipeline: `label -> color/size/caption` mapping.
  - maintain a stable data key strategy (`node.id`, `edge.id`) for diffing and updates.
  - render nodes/edges with label-based styling.
  - support dynamic layouts (minimum: force-directed, hierarchical/dagre-style, radial/concentric, grid, random).
  - support hover/selection details.
- Table view:
  - render tabular rows with pagination/virtualization for large datasets.
- User can switch between graph and table for same result set.
- Oversized result handling is mandatory:
  - define a hard visualization cap (node/edge thresholds).
  - when cap is exceeded, do not render graph by default; show table mode and guidance to refine query.
- Result export is required for graph and table outputs (minimum: JSON, CSV, PNG for graph).

5. Graph Interaction
- User can filter by `label + property + keyword`.
- User can apply edge width mapping using numeric property range.
- User can customize per-label:
  - color
  - size
  - caption field
- User can expand local neighborhood from selected node.
- Optional (configurable) destructive actions: delete node/detach delete with confirmation.

6. Query Authoring UX
- Cypher editor with:
  - run shortcuts
  - command history
  - optional templates/snippets
- Sidebar quick actions to generate starter queries from metadata.
- Optional query builder with grammar-aware suggestions.

7. CSV Graph Initialization
- User can create graph from CSV node/edge files.
- User can map file -> label and choose drop-if-exists.
- Import runs transactionally with rollback on failure.
- Validation errors are surfaced with row-level diagnostics where possible.
- Import must support large files without blocking request lifecycle.
- Implementation must use streaming ingestion and/or asynchronous background job execution.
- API must expose import status/progress and completion/failure retrieval.

8. Settings and Persistence
- Persist local UI preferences (theme, data limits, layout defaults).
- Persist safely in localStorage (or equivalent), not insecure cookie defaults.

## 4.2 Non-Functional Requirements
1. Security
- No SQL string concatenation for user values; use parameterization and validated templates.
- CSRF and session protections appropriate to deployment mode.
- Secrets from environment/config only; never hardcoded.
- Authentication must be required before any API that accesses graph data or executes queries.

2. Performance
- Initial graph render for 5k nodes + 10k edges under 3s on standard developer machine.
- Query result streaming or chunking for large result sets.
- Metadata fetch and graph switch operations under 1s for moderate graph catalogs.
- UI must remain responsive for oversized query results by degrading gracefully to non-graph views.

3. Reliability
- Backend API errors are deterministic and structured.
- Long-running operations (large queries/import) support cancellation and timeout handling.
- No orphaned DB sessions after browser disconnect.

4. Observability
- Structured logs with request/session correlation IDs.
- Metrics: query latency, error rate, import duration, active sessions.

5. Maintainability
- Typed contracts (OpenAPI + FastAPI/Pydantic models required; optional TypeScript client generation for frontend).
- Clear module boundaries: connection, metadata, query, import, visualization.
- High automated test coverage for core services and reducers/hooks.

## 5. API Requirements (Clean Contract)

Base path: `/api`

1. `POST /session/connect`
- Request: connection config.
- Response: session id + sanitized connection summary.

2. `POST /session/disconnect`
- Response: success boolean.

3. `GET /graphs`
- Response: array of graph names + ids.

4. `GET /graphs/{graph}/metadata`
- Response: node labels, edge labels, counts, property keys, db role summary.

5. `POST /queries/execute`
- Request: `{ graph, cypher, params?, options? }`
- Response: `{ columns, rows, rowCount, command, stats }`

6. `POST /queries/{requestId}/cancel`
- Request: cancel metadata (optional reason/user action).
- Response: cancellation status and backend correlation details.

7. `POST /graphs/import/csv`
- Multipart request for streamed upload, or job creation request for async import.
- Response: import job id and initial status.

8. `GET /graphs/import/jobs/{jobId}`
- Response: progress, phase, counters, and terminal summary (created labels, inserted rows, rejected rows, errors).

9. `POST /graphs/{graph}/nodes/{id}/expand`
- Request: depth/limit options.
- Response: subgraph result.

10. `GET /graphs/{graph}/meta-graph`
- Response: discovered label-to-label relationship patterns and counts.

11. `DELETE /graphs/{graph}/nodes/{id}` (optional for v1)
- Request: optional `detach=true`.
- Response: mutation summary.

All endpoints must return standard error envelope:
- `error.code` (stable machine-readable code)
- `error.category` (high-level class)
- `error.message` (human-readable summary)
- `error.details` (optional structured details)
- `error.requestId` (request correlation id)
- `error.timestamp` (ISO-8601 UTC)
- `error.retryable` (boolean)

Error response shape (required):
```json
{
  "error": {
    "code": "QUERY_SYNTAX_ERROR",
    "category": "validation",
    "message": "Cypher syntax error near RETURN",
    "details": {
      "line": 1,
      "column": 24
    },
    "requestId": "req_01HXYZ...",
    "timestamp": "2026-02-14T12:34:56.789Z",
    "retryable": false
  }
}
```

HTTP status mapping (minimum):
- `400` bad request/validation failure
- `401` unauthenticated
- `403` forbidden (if endpoint has policy restrictions)
- `404` not found
- `409` conflict/state conflict
- `413` payload too large
- `422` semantically invalid query/import payload
- `429` rate-limited
- `500` internal server error
- `502` upstream gateway error
- `503` database/backend unavailable
- `504` query/import timeout

Required error codes (minimum set):
- Authentication/session:
  - `AUTH_REQUIRED`
  - `AUTH_INVALID_SESSION`
  - `AUTH_SESSION_EXPIRED`
- Connection/database:
  - `DB_CONNECT_FAILED`
  - `DB_UNAVAILABLE`
  - `GRAPH_NOT_FOUND`
  - `GRAPH_CONTEXT_INVALID`
- Query execution:
  - `QUERY_VALIDATION_ERROR`
  - `QUERY_SYNTAX_ERROR`
  - `QUERY_EXECUTION_ERROR`
  - `QUERY_TIMEOUT`
  - `QUERY_CANCELLED`
- Import:
  - `IMPORT_INVALID_FILE`
  - `IMPORT_VALIDATION_ERROR`
  - `IMPORT_JOB_NOT_FOUND`
  - `IMPORT_FAILED`
- System:
  - `RATE_LIMITED`
  - `INTERNAL_ERROR`

Error code requirements:
- Codes must be stable across releases and documented.
- Frontend behavior must key off `error.code`, not `error.message`.
- `error.details` should include field-level issues for validation errors and row-level issues for CSV import failures.

## 6. Authentication Requirements

Authentication must be explicit and enforced server-side before any graph access or query execution.

1. Authentication Model
- The system must require user authentication to establish an application session.
- First release may use session-cookie authentication (stateful backend), with extensibility for external identity providers later.
- Public/anonymous access is not allowed.

2. Session Security
- Session cookies must be secure (`HttpOnly`, `SameSite`, `Secure` where applicable).
- Session identifiers must be unpredictable and rotated when authentication state changes.
- Session timeout and idle timeout behavior must be configurable.

3. API Enforcement
- Protected APIs must reject unauthenticated requests with clear 401-style responses.
- Authentication checks must execute before database connection use, query execution, or import job creation.
- Frontend checks are advisory only; backend is source of truth.

4. Credential Handling
- Authentication secrets must never be logged or returned in API payloads.
- Credentials and session secrets must be sourced from environment/config, never hardcoded.
- Logout/session invalidation must revoke access immediately.

5. Auditing and Traceability
- Authentication events must be audit-logged:
  - login success/failure
  - logout
  - session expiration/invalidation
- Logs must include timestamp and session/user identifiers for incident analysis.

6. Authentication Test Requirements
- Integration tests must cover:
  - successful authentication and protected API access
  - rejected unauthenticated requests
  - invalid/expired session handling
  - logout invalidation behavior
  - session timeout behavior

## 7. Data and Query Handling Requirements

- Support AGE agtype parsing for:
  - vertex
  - edge
  - path
  - nested map/list/scalar structures
- Provide a canonical internal element model:
  - Node: `id`, `label`, `properties`
  - Edge: `id`, `label`, `source`, `target`, `properties`
- Preserve row-level tabular result in addition to extracted graph elements.
- Prevent implicit lossy conversions.
- 64-bit integer safety is mandatory end-to-end:
  - IDs and other int8 values must not be represented as unsafe JS `Number`.
  - API and frontend must use a BigInt-safe serialization/parsing strategy.

## 8. UX Requirements

1. Workspace model
- Multi-result panels/tabs with close, refresh, pin.
- Non-blocking execution indicator and cancel support.
- Query editor must include a parameters input block (JSON) for `$param` execution.

2. Graph view
- Smooth pan/zoom and selection behavior.
- Deterministic default colors (no random assignment drift across panels unless configured).
- Legend controls for node/edge labels.

3. Error UX
- Distinguish transport, auth/session, syntax, and runtime DB errors.
- Keep failed query text in editor for correction.
- Clearly indicate cancellation state vs timeout vs server failure.

4. Accessibility
- Keyboard navigation for core actions.
- Contrast-compliant themes.
- ARIA labels for controls.

## 9. Testing Requirements

1. Backend
- Unit tests for agtype conversion and query services.
- Integration tests against AGE-enabled PostgreSQL for:
  - connect/disconnect
  - metadata fetch
  - execute query (read/write)
  - csv import (success + rollback)

2. Frontend
- Component/integration tests for:
  - connect flow
  - query execution flow
  - graph/table toggle
  - filter and legend customization

3. End-to-end
- Smoke suite covering core user journey from connect to visual exploration.

4. Integration Test Plan (Detailed)

1. Test Environments
- `INT-SMOKE`: single PostgreSQL + AGE version for fast CI gating.
- `INT-FULL`: matrix across supported PostgreSQL and AGE versions.
- `INT-PERF`: targeted large-graph scenarios for latency and memory checks.

2. Version Matrix
- PostgreSQL: every supported major version for release (for example, 14/15/16 as finalized in compatibility policy).
- Apache AGE: minimum supported AGE release and latest supported AGE release.
- Every matrix cell must run core integration contract tests before release.

3. Core API Integration Scenarios
- Session lifecycle:
  - connect success
  - invalid credentials
  - disconnect idempotency
  - stale session handling
- Graph discovery and metadata:
  - list graphs with empty and populated DBs
  - metadata correctness for node labels, edge labels, and property keys
  - graph switching consistency
  - graph-switch leakage prevention (query on Graph X must not resolve against Graph Y)
- Query execution:
  - read-only query returning vertices/edges/paths
  - write query (create/update/delete) with result envelope checks
  - malformed cypher and DB runtime error paths
  - timeout/cancellation behavior
  - safe/read-only mode rejection of mutating clauses
- CSV import:
  - valid async/streamed import with expected created labels and inserted rows
  - invalid row handling and diagnostics
  - rollback verification on failure (no partial writes)
  - drop-if-exists behavior and idempotent re-import
  - progress/status endpoint correctness for long-running imports
- Optional mutation endpoints:
  - node deletion (`detach=true/false`) and graph consistency checks
  - neighborhood expansion contract and limits

4. Data Integrity Assertions
- Validate canonical element mapping (`Node`, `Edge`) against raw AGE responses.
- Validate that path/scalar/map/list rows are preserved in table results.
- Validate no lossy type conversion for ids and numeric properties.
- Validate 64-bit integer fidelity across API serialization/deserialization and frontend consumption.

5. Concurrency and Isolation
- Parallel sessions against same DB with isolated state.
- Concurrent query execution from separate sessions.
- Concurrent import + read/query operations with deterministic outcomes.

6. Security-Focused Integration Cases
- Reject unsafe/malformed payloads at API boundary.
- Verify secrets are never returned in API responses.
- Verify authentication enforcement on protected endpoints and invalid session rejection.

7. Performance Checks (Integration-Level)
- Query latency thresholds for representative datasets.
- Metadata fetch latency thresholds on multi-graph catalogs.
- Import duration and memory bounds for large CSV batches.

8. CI Execution Strategy
- Pull request: run `INT-SMOKE` + critical frontend integration tests.
- Main branch/nightly: run `INT-FULL` matrix + extended E2E smoke.
- Release candidate: run full matrix plus `INT-PERF` and produce baseline report.

9. Test Data Management
- Deterministic seed datasets for small/medium/large graph shapes.
- Fixtures for edge cases: missing properties, dense hubs, long paths, mixed-type properties.
- Automatic teardown/reset per test run to avoid cross-test contamination.

## 10. Security Checklist (Release Gate)

All items below must be satisfied before production release.

1. Authentication and Session Security
- Authentication enforced on all protected endpoints.
- Session cookies configured with `HttpOnly`, `SameSite`, and `Secure` (in HTTPS environments).
- Session rotation on authentication state changes (login/logout).
- Session timeout and idle timeout configured and validated.

2. Secrets and Configuration
- No hardcoded secrets in source code or repository history.
- All secrets sourced from environment/secret manager.
- Secret values never logged in plaintext.

3. API and Input Validation
- Strict schema validation on all API request payloads.
- CSV import input validation with row-level error reporting.
- Query parameter payload validation before DB execution.
- Request size limits configured for all upload/query endpoints.

4. Database and Query Safety
- No unsafe SQL string concatenation for user-controlled values.
- Parameterized query execution enforced where applicable.
- Safe/read-only mode behavior validated when enabled.
- Query timeout and cancellation controls enabled and tested.

5. Transport and Network
- TLS enabled for deployed API endpoints.
- CORS policy restricted to approved frontend origins.
- Service deployed in approved private network boundary for DB access.

6. Error and Data Exposure
- Standard error envelope returned consistently.
- Internal stack traces not exposed to clients.
- Sensitive fields (credentials/secrets/tokens) excluded from API responses.

7. Logging, Audit, and Monitoring
- Authentication events logged (success/failure/logout/session expiry).
- Mutating operations logged with request/session identifiers.
- Security-relevant alerts configured (repeated auth failures, abnormal import/query errors).

8. Dependency and Supply Chain
- Dependency vulnerability scan executed with no unresolved critical findings.
- Lockfiles committed and dependency versions pinned/reviewed.
- Third-party packages reviewed for license and maintenance risk.

9. Verification and Sign-Off
- Security-focused integration tests pass (auth, invalid session, protected endpoints).
- Manual penetration sanity checks completed (auth bypass, injection attempts, broken access paths).
- Final security sign-off recorded by designated owner before release.

## 11. Migration and Compatibility Requirements

- Preserve existing high-value user workflows:
  - run Cypher and visualize graph/table
  - sidebar metadata-driven query generation
  - CSV graph initialization
- Provide migration notes for deprecated commands/features (`:play`, `:csv` frame).
- Provide compatibility matrix for PostgreSQL and AGE versions supported.

## 12. Implementation Guardrails for Clean-Room Build

- Do not copy source code from the existing implementation.
- Re-derive behavior from this requirements document and black-box tests.
- Define fresh architecture and contracts before coding UI details.
- Enforce security and testability as release gates.

## 13. Release Acceptance Criteria (MVP)

1. User can connect to an AGE database and list/switch graphs.
2. User can execute Cypher and see both graph and table outputs.
3. Graph interactions work: filter, layout change, label styling, neighborhood expansion.
4. CSV import creates graph data transactionally with clear status reporting.
5. No known broken routes/features in shipped UI.
6. Automated test suite passes in CI with AGE integration tests.
7. Security checklist (Section 10) passes with documented sign-off.

## 14. Suggested Phasing

1. Phase 1: API core + secure connection/session + query execution.
2. Phase 2: metadata + graph/table visualization + interaction controls.
3. Phase 3: CSV import + advanced UX (builder, tutorial, optional delete).
4. Phase 4: hardening (perf, observability, compatibility, documentation).
