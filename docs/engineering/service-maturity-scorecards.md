# Service Operational Maturity Scorecards & Governance

This document codifies the **Level 3 Operational Maturity Standard** and governance tracks evaluated for all components and services in the Backstage Software Catalog.

Evaluations are performed continuously by the Backstage backend scoring engine (`@vitruviansoftware/backstage-backend/src/scorecards`) using live fact collectors (verifying physical repository files, CODEOWNERS bindings, live Uptime Kuma health signals, and CI/CD build pass rates) rather than static YAML declarations.

---

## 1. System Architecture & Data Flow

The scorecard platform replaces static catalog heuristics with an authoritative server-side evaluation engine powered by asynchronous fact collectors, in-memory TTL caching, timeout protection, fail-closed security, and archetype-fair scoring.

```mermaid
flowchart TB
    subgraph Frontend["Backstage Frontend (React & Material-UI)"]
        direction TB
        Page["Entity Overview / Catalog Page"]
        Card["EntityScorecardCard.tsx<br/>(Dynamic Radar Breakdown + Actionable Checklist)"]
        Fallback["scorecard.ts<br/>(Graceful Degraded Fallback Mode)"]
        
        Page --> Card
        Card -.->|Network/API Error| Fallback
    end

    subgraph Backend["Backstage Backend Plugin (@vitruviansoftware/backstage-backend)"]
        direction TB
        Router["/api/scorecards/entities/:kind/:namespace/:name<br/>(Express Promise Router)"]
        
        subgraph Engine["Authoritative Evaluator Engine (evaluator.ts)"]
            ArchetypeDetect["Archetype Classifier<br/>(service | tool | website | library)"]
            TrackEval["Multi-Track Score Calculator<br/>(Security | Reliability | Quality | Delivery)"]
            LevelAgg["Aggregate Level & Progress Matrix<br/>(Bronze L1 | Silver L2 | Gold L3)"]
            
            ArchetypeDetect --> TrackEval --> LevelAgg
        end
        
        subgraph Collectors["Asynchronous Fact Collectors (factCollectors.ts)"]
            direction TB
            FC_Sec["collectSecurityFacts<br/>• CODEOWNERS Async Parser<br/>• LICENSE Standard Check"]
            FC_Rel["collectRunbookFacts & collectUptimeFacts<br/>• docs/runbooks/*.md Search<br/>• Live Kuma Probe (3s Timeout)"]
            FC_Qual["collectCiQualityFacts<br/>• GitHub Actions Workflow API<br/>• In-Memory TTL Cache (5m)"]
            FC_Del["collectRuntimeFacts<br/>• Cloud Run / K8s / GoReleaser"]
        end
        
        Router --> Engine
        Engine --> Collectors
    end

    subgraph Sources["Live Monorepo & Infrastructure Data Sources"]
        direction TB
        GitFS["Monorepo Filesystem<br/>(CODEOWNERS, LICENSE, docs/runbooks)"]
        GHA["GitHub Actions API<br/>(CI Run Statistics & Pass Rates)"]
        Kuma["Uptime Kuma Probe<br/>(Live HTTP / Health Probes)"]
        Catalog["Backstage Catalog<br/>(Entity YAML Specs & Annotations)"]
    end

    Card ==>|HTTP GET /api/scorecards/...| Router
    Engine -.->|Read Spec| Catalog
    FC_Sec --> GitFS
    FC_Rel --> GitFS
    FC_Rel --> Kuma
    FC_Qual --> GHA
    FC_Del --> GitFS
```

---

## 2. Evaluation Lifecycle & Asynchronous Fact Collection

```mermaid
sequenceDiagram
    autonumber
    actor Developer as Developer / Viewer
    participant UI as EntityScorecardCard (Frontend)
    participant API as Scorecards Router (Backend)
    participant Evaluator as Evaluation Engine
    participant Cache as Memory TTL Cache (5m)
    participant Sources as Live Probes (GitHub/Kuma/FS)

    Developer->>UI: Navigates to Component Page
    UI->>API: GET /api/scorecards/entities/component/default/tabula
    API->>Evaluator: evaluateEntityScorecard(entity, repoRoot, githubToken)
    
    par Live Fact Collection
        Evaluator->>Sources: Parse CODEOWNERS & LICENSE
        Evaluator->>Sources: Scan docs/runbooks/tabula.md
        Evaluator->>Cache: Check GitHub Actions Pass Rate
        alt Cache Hit
            Cache-->>Evaluator: Return cached CI pass rate
        else Cache Miss
            Evaluator->>Sources: Fetch Workflow Runs (with 4s timeout)
            Sources-->>Cache: Store result (TTL: 300s)
            Cache-->>Evaluator: Return CI pass rate
        end
        Evaluator->>Sources: Probe Live Uptime (with 3s timeout)
    end

    Evaluator->>Evaluator: Apply Archetype Rules (service vs tool vs website vs library)
    Evaluator->>Evaluator: Calculate Track Scores & Bronze/Silver/Gold Levels
    Evaluator-->>API: Return EvaluatedScorecard JSON
    API-->>UI: HTTP 200 OK (Scorecard Payload)
    UI-->>Developer: Render Radar Chart, Track Badges & Remediation Items
```

---

## 3. Multi-Track Evaluation Dimensions

Every catalog component is evaluated across **four operational governance tracks**:

```mermaid
flowchart LR
    subgraph Level1["🥉 Bronze (Level 1): Foundation"]
        L1_Sec["Owner Assigned"]
        L1_Rel["CI Pipeline Configured"]
        L1_Qual["Description & TechDocs"]
        L1_Del["Lifecycle & Release Model"]
    end

    subgraph Level2["🥈 Silver (Level 2): Operations"]
        L2_Sec["CODEOWNERS Enforced"]
        L2_Rel["Runtime Binding Active"]
        L2_Qual["System & Domain Bound"]
        L2_Del["Environment Promotion Ladder"]
    end

    subgraph Level3["🥇 Gold (Level 3): Production Standard"]
        L3_Sec["License Compliance Verified"]
        L3_Rel["Live Uptime + Incident Runbook"]
        L3_Qual["API Contracts & Topology Mapped"]
        L3_Del["Published Build Artifacts"]
    end

    Level1 ==> Level2 ==> Level3
```

### 🛡️ Track 1: Security & Governance
- **Level 1 (Bronze)**: `spec.owner` assigned to an active team.
- **Level 2 (Silver)**: Owner verified in `.github/CODEOWNERS` with repository access.
- **Level 3 (Gold)**: Automated license header conformance (`license-check`) and zero critical vulnerabilities.

### 📈 Track 2: Reliability & Operability
- **Level 1 (Bronze)**: Declared deployment/release workflow.
- **Level 2 (Silver)**: Verified runtime binding (Cloud Run services, k3s Kubernetes ID, or GoReleaser / npm packaging).
- **Level 3 (Gold)**:
  - *Microservices*: Live Uptime Kuma health check (UP) + Verified Incident Triage Runbook section in `docs/operations/incident-triage-runbook.md`.
  - *Developer Tools / Libraries*: CI/CD build pass rate >= 80% with automated multi-architecture packaging.

### 📚 Track 3: Quality & API Contracts
- **Level 1 (Bronze)**: Description > 10 characters + `backstage.io/techdocs-ref` configured.
- **Level 2 (Silver)**: Lifecycle (`production`/`development`) and System hierarchy declared.
- **Level 3 (Gold)**:
  - *Microservices*: Declared API contracts (`providesApis`/`consumesApis`) + Infrastructure topology (`dependsOn`).
  - *Developer Tools / Libraries*: Standalone repository export mirror binding (`vitruvian.dev/mirror`) + CLI usage documentation.

### 🚀 Track 4: Delivery & SDLC
- **Level 1 (Bronze)**: Declared release model (`vitruvian.dev/release-model`).
- **Level 2 (Silver)**: Environment promotion ladder declared (`vitruvian.dev/environments`).
- **Level 3 (Gold)**: Published distribution channel (GHCR container image, npm registry package, or GitHub Release binary assets).

---

## 4. Archetype-Aware Governance

Criteria dynamically adapt based on **`spec.type`**:

| Archetype | Description | Reliability Track Requirements | Quality Track Requirements |
| :--- | :--- | :--- | :--- |
| **`service`** | Backend APIs & Daemons | Live Uptime Kuma monitor + Incident Triage Runbook | `providesApis` / `consumesApis` + `dependsOn` |
| **`tool`** | Developer CLI & Desktop Apps | CI/CD build pass rate >= 80% (Uptime/Runbook N/A) | `vitruvian.dev/mirror` + CLI usage docs |
| **`website`** | Static Web Apps | Ingress / TLS health check (Runbook N/A) | TechDocs / Storybook docs |
| **`library`** | Packages & SDKs | npm / pkg.go.dev registry release (Uptime N/A) | Type definitions (`.d.ts` / Go doc) |

---

## 5. Component Maturity Audit Matrix

| Component | Archetype | Owner | Lifecycle | Security | Reliability | Quality | Delivery | Overall Tier |
| :--- | :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **`tabula`** | `service` | `tabula-team` | `production` | L3 | L3 | L3 | L3 | 🥇 **Gold** |
| **`oauth-user-inspector`** | `service` | `oauth-user-inspector-team` | `production` | L3 | L3 | L3 | L3 | 🥇 **Gold** |
| **`backstage`** | `service` | `platform-team` | `production` | L3 | L3 | L3 | L3 | 🥇 **Gold** |
| **`buzz`** | `service` | `platform-team` | `production` | L3 | L3 | L3 | L3 | 🥇 **Gold** |
| **`mcp-slack`** | `service` | `mcp-slack-team` | `production` | L3 | L3 | L3 | L3 | 🥇 **Gold** |
| **`devx`** | `tool` | `devx-team` | `production` | L3 | L3 | L3 | L3 | 🥇 **Gold** |
| **`homelab`** | `tool` | `homelab-team` | `production` | L3 | L3 | L3 | L3 | 🥇 **Gold** |
| **`nexus-agent`** | `tool` | `nexus-agent-team` | `production` | L3 | L3 | L3 | L3 | 🥇 **Gold** |
| **`whoami`** | `service` | `platform-team` | `production` | L3 | L3 | L3 | L3 | 🥇 **Gold** |
| **`storybook`** | `website` | `platform-team` | `production` | L3 | L3 | L3 | L3 | 🥇 **Gold** |
