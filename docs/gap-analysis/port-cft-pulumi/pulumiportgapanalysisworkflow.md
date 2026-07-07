# Workflow: `pulumi-port-gap-analysis`

This is the `Workflow` tool script used to produce `GAP-REPORT.md` — a
verified list of functional gaps between `terraform-example-foundation`
and its two Pulumi ports (`pulumi_go-example-foundation`,
`pulumi_ts-example-foundation`), backed by the shared component library
`pulumi-library`.

## What it does

Three phases:

1. **Find** — 15 independent agents, each scoped to one stage or
   cross-cutting dimension (`0-bootstrap` … `5-app-infra`,
   `policy-library`, CI/CD tooling, tests, docs, a Go stub sweep, a TS
   stub sweep, library Go/TS parity, upstream git drift). Each agent
   exhaustively enumerates the Terraform behavior in its area and traces
   every capability into the port repos and `pulumi-library`, returning a
   structured list of claimed gaps (title, description, evidence,
   severity).
2. **Verify** — every claimed gap is handed to an independent adversarial
   verifier agent whose job is to try to *refute* it (confirm the TF side
   really exists, hunt for an equivalent under any name in the ports and
   the library, and sanity-check the claimed severity). Verification runs
   in a `pipeline()` so a dimension's claims start verifying the moment
   that dimension's finder returns — no barrier wait for the slowest
   finder.
3. **Critique** — a final completeness-critic agent reviews the whole
   confirmed list plus every finder's coverage notes, spot-checks a few
   areas itself, and reports anything the 15 finders missed.

The script returns `{ confirmed, refutedCount, refutedTitles, unverified,
critique, coverage }`. Post-processing outside the script (not shown
here) deduplicates near-identical findings from different finders that
converged on the same root cause, then renders the markdown report.

## Reusing it

- **Different repos**: edit the `REPOS` constant (the four paths and
  their one-line descriptions) — everything else is generic.
- **Different stage names**: edit the `STAGES` array.
- **Different or additional dimensions**: edit `extraFinders` — each
  entry is just `{ key, prompt }`.
- **Re-run without resending the script**: `Workflow({ scriptPath: '<path
  this was saved to>', resumeFromRunId: '<prior run id>' })` — completed
  `agent()` calls (same prompt + opts) replay from cache; only new/edited
  ones re-run. This is what let the run survive two mid-run rate-limit
  hits without redoing any finished work.

## Full script

```javascript
export const meta = {
  name: 'pulumi-port-gap-analysis',
  description: 'Compare terraform-example-foundation against Pulumi Go/TS ports and find verified gaps',
  phases: [
    { title: 'Find', detail: 'one agent per stage/dimension comparing TF vs Go vs TS' },
    { title: 'Verify', detail: 'adversarially refute each claimed gap' },
    { title: 'Critique', detail: 'completeness check on the final list' },
  ],
}

const REPOS = `Repos on local disk (all checked out on the same branch):
- /home/user/terraform-example-foundation  — the reference implementation (Google's terraform-example-foundation)
- /home/user/pulumi_go-example-foundation  — the Pulumi Go port (mirrors the stage layout: 0-bootstrap ... 5-app-infra, policy-library, test, helpers, build, scripts, docs)
- /home/user/pulumi_ts-example-foundation  — the Pulumi TypeScript port (same layout)
- /home/user/pulumi-library                — shared Pulumi component library used by BOTH ports (go/ and ts/ subdirectories). Ports import components from here, so ALWAYS check this repo before declaring something missing from a port.`

const RULES = `Report only GENUINE FUNCTIONAL gaps in the ports:
- Terraform resources / modules / behaviors with no Pulumi equivalent anywhere (port repo OR pulumi-library)
- Features or configuration options the Terraform code supports but the port hardcodes or omits
- Stubbed / TODO / placeholder / commented-out code in the ports
- Outputs the Terraform stage exports (and later stages consume) that the port does not export
- Validation, preconditions, or IAM/org-policy bindings present in TF but absent in the port
- Divergent behavior (different defaults, missing conditional branches, missing for_each expansion cases)
- Gaps present in one port but not the other (Go/TS drift)

Do NOT report:
- Naming/style/layout differences with equivalent behavior
- Terraform state/backend/tfvars mechanics, provider version pins, or .tf boilerplate that has a different-but-equivalent Pulumi mechanism (stack config, ESC, etc.) — only report if the port lacks the capability entirely
- Documentation wording differences (unless whole doc/guide files are missing)
- Speculation. Every gap needs concrete evidence: cite the TF file/resource that exists and the port location(s) you checked where the equivalent should be.

Severity: critical = deployment would fail or a security control is silently absent; major = meaningful feature/resource missing; minor = small option/output/validation missing; info = worth knowing, not blocking.`

const GAPS_SCHEMA = {
  type: 'object',
  required: ['gaps', 'coverageNotes'],
  properties: {
    gaps: {
      type: 'array',
      items: {
        type: 'object',
        required: ['port', 'area', 'title', 'description', 'evidence', 'severity'],
        properties: {
          port: { type: 'string', enum: ['go', 'ts', 'both'] },
          area: { type: 'string', description: 'stage or dimension, e.g. 1-org' },
          title: { type: 'string', description: 'one-line name of the missing thing' },
          description: { type: 'string', description: 'what is missing and why it matters' },
          evidence: { type: 'string', description: 'TF file/resource that exists + port paths checked where it is absent' },
          severity: { type: 'string', enum: ['critical', 'major', 'minor', 'info'] },
        },
      },
    },
    coverageNotes: { type: 'string', description: 'what you compared and anything you could not fully check' },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['isRealGap', 'confidence', 'explanation'],
  properties: {
    isRealGap: { type: 'boolean' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    explanation: { type: 'string' },
    correction: { type: 'string', description: 'if partially wrong, the corrected statement of the gap' },
  },
}

const STAGES = [
  '0-bootstrap',
  '1-org',
  '2-environments',
  '3-networks-svpc',
  '3-networks-hub-and-spoke',
  '4-projects',
  '5-app-infra',
  'policy-library',
]

const stageFinders = STAGES.map((stage) => ({
  key: `stage:${stage}`,
  prompt: `You are auditing Pulumi ports of Google's terraform-example-foundation for missing functionality.

${REPOS}

Your assigned area: the \`${stage}\` directory (compare it across all three implementations; the same directory name exists in each repo).

Method:
1. Exhaustively enumerate the Terraform implementation of ${stage}: every .tf file including envs/, modules/ subdirectories and any repo-local modules it sources; list every resource type, module call, meaningful variable, output, IAM binding, org policy, log sink, and conditional behavior.
2. Read the Go port's ${stage} and the TS port's ${stage}. Follow their imports into /home/user/pulumi-library (go/ and ts/) — much of the resource logic lives in library components.
3. Diff functionality, not text. For every TF capability, find where the port implements it or record it as a gap.

${RULES}

Return the structured gap list. In coverageNotes, state which TF files/modules you enumerated and any parts you could not fully trace.`,
}))

const extraFinders = [
  {
    key: 'cicd-tooling',
    prompt: `You are auditing Pulumi ports of Google's terraform-example-foundation for missing functionality in CI/CD and deployment tooling.

${REPOS}

Your assigned area: build pipeline and operational tooling — the \`build/\`, \`scripts/\`, \`helpers/\`, and \`Makefile\` content of each repo, plus the CI/CD wiring created by 0-bootstrap (cloudbuild yaml files, tf-wrapper.sh / its Pulumi equivalent, Jenkins/GitHub/GitLab/local build-type support, foundation deployer images).

Method:
1. Enumerate what terraform-example-foundation ships: build/*.yaml cloudbuild configs, build/tf-wrapper.sh capabilities (plan/apply/validate per env branch, policy checks via gcloud terraform vet), helpers/ (e.g. foundation-deployer app), scripts/, and the multiple CICD build types supported in 0-bootstrap (cb.tf, jenkins.tf, github.tf, gitlab.tf, terraform_cloud.tf, local build type if present).
2. Compare against both ports' equivalents (pipeline wrappers, policy-check integration, deployer helpers, supported build types).
3. Also check /home/user/pulumi-library for shared CI/CD components.

${RULES}

Return the structured gap list with concrete evidence.`,
  },
  {
    key: 'tests',
    prompt: `You are auditing Pulumi ports of Google's terraform-example-foundation for missing TEST coverage relative to the reference.

${REPOS}

Your assigned area: the \`test/\` trees. terraform-example-foundation has extensive Go integration tests (test/integration/<stage>/...) using terraform-google-modules/cloud-foundation-toolkit test framework, plus setup/ fixtures and validator policies used in tests.

Method:
1. Enumerate the TF repo's test suites per stage and what each asserts (resources existence, IAM, org policies, networking).
2. Compare with pulumi_go-example-foundation/test and pulumi_ts-example-foundation/test (unit tests, property tests, integration tests, mocks). Note stages with no equivalent coverage and assertion categories that were dropped.
3. Check whether each port's tests actually run (wired into Makefile / CI config) or are dead code.

${RULES} Focus on missing test coverage per stage, not test framework differences. A stage whose TF tests assert 30 properties while the port asserts 3 is a gap worth quantifying roughly.

Return the structured gap list.`,
  },
  {
    key: 'docs',
    prompt: `You are auditing Pulumi ports of Google's terraform-example-foundation for missing documentation and operator guidance.

${REPOS}

Your assigned area: README.md files (root and per-stage), docs/ directory, ERRATA.md, upgrade guides, and deployment step-by-step instructions.

Method:
1. Enumerate the TF repo's docs: root README deployment overview, per-stage READMEs with prerequisites/usage/inputs/outputs tables, docs/*.md (FAQ, GLOSSARY, TROUBLESHOOTING, upgrade guides, assured-workloads, etc.).
2. Compare against both ports' docs. Report whole missing documents, per-stage READMEs that are missing or skeletal, and instructions that still reference Terraform commands (copy-paste rot) in the ports.

${RULES} Only report missing/skeletal/incorrect docs, not wording differences. Severity for docs gaps is at most 'minor' unless instructions are actively wrong ('major').

Return the structured gap list.`,
  },
  {
    key: 'stub-sweep-go',
    prompt: `You are auditing the Pulumi GO port of Google's terraform-example-foundation for incomplete code.

${REPOS}

Your assigned area: a full sweep of /home/user/pulumi_go-example-foundation AND /home/user/pulumi-library/go for markers of unfinished work.

Method: grep exhaustively for TODO, FIXME, XXX, HACK, "not implemented", "unimplemented", "placeholder", "stub", "for now", "temporary", "hardcoded", "hard-coded", "future", "later", "skip", panic("..."), commented-out resource blocks, functions that return empty/nil where a real implementation is expected, and Pulumi resources constructed with obviously-defaulted/empty args. Read the surrounding code to judge whether each hit is a real functional gap or benign. Also check for stage directories or files that exist but are near-empty relative to their TS/TF counterparts.

${RULES}

Return the structured gap list (port: 'go' for all findings, area: the stage/dir the finding is in).`,
  },
  {
    key: 'stub-sweep-ts',
    prompt: `You are auditing the Pulumi TYPESCRIPT port of Google's terraform-example-foundation for incomplete code.

${REPOS}

Your assigned area: a full sweep of /home/user/pulumi_ts-example-foundation AND /home/user/pulumi-library/ts for markers of unfinished work.

Method: grep exhaustively for TODO, FIXME, XXX, HACK, "not implemented", "unimplemented", "placeholder", "stub", "for now", "temporary", "hardcoded", "hard-coded", "future", "later", "skip", throw new Error("not"), @ts-ignore / @ts-expect-error, any-casts hiding missing config, commented-out resource blocks, and functions returning empty objects where real implementation is expected. Read the surrounding code to judge whether each hit is a real functional gap or benign. Also check for stage directories or files that exist but are near-empty relative to their Go/TF counterparts.

${RULES}

Return the structured gap list (port: 'ts' for all findings, area: the stage/dir the finding is in).`,
  },
  {
    key: 'library-parity',
    prompt: `You are auditing /home/user/pulumi-library — the shared component library used by Pulumi Go and TS ports of Google's terraform-example-foundation.

${REPOS}

Your assigned area: parity WITHIN the library: (a) Go components vs TS components — enumerate every component/package under go/ and ts/, and report components that exist in one language but not the other, or whose feature sets/options diverge; (b) each component vs the upstream terraform-google-modules module it mirrors (e.g. project-factory, network, log-export, org-policy, iam, kms, service-accounts, cloud-router, cloud-nat, bastion, etc. — infer the mirrored module from names/comments and compare against how terraform-example-foundation USES that module: any module argument used by terraform-example-foundation that the library component cannot express is a gap).

${RULES}

Return the structured gap list (port: 'go', 'ts', or 'both' depending on which side lacks the feature; area: 'pulumi-library/<component>').`,
  },
  {
    key: 'upstream-drift',
    prompt: `You are auditing whether recent changes to Google's terraform-example-foundation have been incorporated into its Pulumi ports.

${REPOS}

Your assigned area: upstream drift. Run \`git -C /home/user/terraform-example-foundation log --oneline -40\` and inspect the last ~9 months of feature/fix commits (e.g. 'add local build type', 'user validation using TestIamPermissions api', and anything else functional). For each functional upstream change, check whether the Go and TS ports (and pulumi-library) contain the equivalent behavior. Use \`git -C <repo> log --oneline -30\` on the ports to see what they claim to have ported. Diff-read the upstream commits that look functional (\`git show <sha> --stat\` then targeted file reads).

${RULES}

Return the structured gap list (area: 'upstream-drift', include the upstream commit sha in evidence).`,
  },
]

const FINDERS = [...stageFinders, ...extraFinders]

phase('Find')
log(`Comparing ${STAGES.length} stages + ${extraFinders.length} cross-cutting dimensions across TF reference, Go port, TS port, and shared library`)

const results = await pipeline(
  FINDERS,
  (f) => agent(f.prompt, { label: `find:${f.key}`, phase: 'Find', schema: GAPS_SCHEMA }),
  (found, f) => {
    if (!found || !found.gaps || found.gaps.length === 0) {
      return { finder: f.key, coverageNotes: found ? found.coverageNotes : 'agent failed', gaps: [] }
    }
    return parallel(
      found.gaps.map((g) => () =>
        agent(
          `You are an adversarial verifier. A reviewer claims the following functionality is MISSING from a Pulumi port of Google's terraform-example-foundation. Your job is to try hard to REFUTE the claim.

${REPOS}

CLAIM:
- Affected port(s): ${g.port}
- Area: ${g.area}
- Title: ${g.title}
- Description: ${g.description}
- Evidence given: ${g.evidence}
- Claimed severity: ${g.severity}

Method:
1. First confirm the Terraform side: does the cited TF functionality actually exist in /home/user/terraform-example-foundation as described? If not, the claim is refuted.
2. Then hunt for an equivalent in the affected port(s) under ANY name: grep the port repo(s) AND /home/user/pulumi-library (both go/ and ts/) for the resource type, GCP API names, related keywords, and plausible alternative spellings. Follow imports. Equivalent behavior implemented differently still refutes the claim.
3. Judge severity honestly: if the gap is real but the claimed severity is inflated (e.g. it's an informational output nothing consumes), say so in 'correction'.

Default to isRealGap=false unless the evidence clearly shows the functionality is absent everywhere it could live. Set confidence based on how exhaustively you searched.`,
          { label: `verify:${g.title.slice(0, 50)}`, phase: 'Verify', schema: VERDICT_SCHEMA }
        ).then((v) => ({ ...g, verdict: v }))
      )
    ).then((verified) => ({
      finder: f.key,
      coverageNotes: found.coverageNotes,
      gaps: verified.filter(Boolean),
    }))
  }
)

const clean = results.filter(Boolean)
const allGaps = clean.flatMap((r) => r.gaps || [])
const confirmed = allGaps.filter((g) => g.verdict && g.verdict.isRealGap)
const refuted = allGaps.filter((g) => g.verdict && !g.verdict.isRealGap)
const unverified = allGaps.filter((g) => !g.verdict)
log(`${allGaps.length} claimed gaps → ${confirmed.length} confirmed, ${refuted.length} refuted, ${unverified.length} verifier-failed`)

phase('Critique')
const critique = await agent(
  `You are a completeness critic for a gap analysis of Pulumi ports (Go + TS) of Google's terraform-example-foundation.

${REPOS}

The analysis covered these dimensions: ${FINDERS.map((f) => f.key).join(', ')}.
Confirmed gaps so far (title | port | area | severity):
${confirmed.map((g) => `- ${g.title} | ${g.port} | ${g.area} | ${g.severity}`).join('\n') || '(none)'}

Finder coverage notes:
${clean.map((r) => `[${r.finder}] ${String(r.coverageNotes).slice(0, 400)}`).join('\n')}

Your job: identify what this analysis MISSED. Spot-check 3-5 places yourself: pick a couple of TF files at random depth (e.g. a modules/ subdir in 1-org or 4-projects) and verify the ports really cover them; check anything the coverage notes admit was not fully traced; look for whole directories in the TF repo absent from the dimension list. Report concrete missed gaps (same evidence standard: TF path that exists + port paths checked) and any dimension that needs a deeper pass. Do not repeat confirmed gaps.`,
  {
    label: 'completeness-critic',
    phase: 'Critique',
    effort: 'high',
    schema: {
      type: 'object',
      required: ['missedGaps', 'assessment'],
      properties: {
        missedGaps: GAPS_SCHEMA.properties.gaps,
        assessment: { type: 'string', description: 'overall judgment of analysis completeness' },
      },
    },
  }
)

return {
  confirmed,
  refutedCount: refuted.length,
  refutedTitles: refuted.map((g) => `${g.title} (${g.verdict.explanation.slice(0, 160)})`),
  unverified,
  critique,
  coverage: clean.map((r) => ({ finder: r.finder, notes: r.coverageNotes, claimed: (r.gaps || []).length })),
}
```
