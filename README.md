# github-actions-scripts

A collection of reusable GitHub Actions composite actions for Akka projects.

- [`setup_global_resolver`](#setup_global_resolver) — configure sbt, Maven, and Gradle to resolve dependencies from the Akka repository
- [`verify_pom`](#verify_pom) — keep checked-in, sbt-generated `pom.xml` files in sync
- [`artifact_bom_validation`](#artifact_bom_validation) — fail the build when the artifact BOM is out of sync

---

## `setup_global_resolver`

Globally configures **sbt, Maven, and Gradle** to resolve dependencies from the Akka repository. Use this in CI workflows to inject Akka resolvers without modifying individual project source files.

### What it does

- Injects Akka release and snapshot repository URLs into global config files for sbt, Maven, and Gradle
- Optionally configures Sonatype Maven Central deployment credentials from environment variables
- Configures a Maven HTTP blocker to prevent insecure repository connections
- Optionally sets up sbt scripted test resolvers for plugin development

It writes to the following locations on the runner:

| Build tool | File |
| :--- | :--- |
| sbt | `~/.sbt/1.0/resolvers.sbt` |
| sbt scripted tests | `global/resolvers.sbt` for each test case under the plugin's `src/sbt-test` |
| Gradle | `~/.gradle/init.d/akka-resolvers.init.gradle` |
| Maven | `~/.m2/settings.xml` |

> **Run this _after_ `actions/setup-java`.** `setup-java` generates its own `~/.m2/settings.xml`, so if it runs after this action it will overwrite the Akka Maven configuration. Always place `setup-java` — and any other step that writes `~/.m2/settings.xml` — before this action.

### Installation

Reference the action directly in your workflow using the `akka/github-actions-scripts/setup_global_resolver` path:

```yaml
- name: Setup Global Akka Resolver
  uses: akka/github-actions-scripts/setup_global_resolver@main
```

No checkout of this repository is required.

### Inputs

| Input | Required | Default | Description |
| :--- | :--- | :--- | :--- |
| `sbt-plugin-project-name` | No | `''` | The name of the sbt plugin project directory. When provided, configures resolvers for each `sbt-test` scripted test case found under that project. |
| `maven-mirror-control` | No | `''` | Set to `NO_MIRROR` to skip injecting `<mirrors>` into Maven `settings.xml`. Required for projects using `protoc`, which manages its own resolver and does not handle mirrored repositories. **Note:** this also disables the Maven HTTP blocker, since it lives inside the same `<mirrors>` block. |

### Environment Variables

Set these as GitHub Actions secrets/variables if you need Sonatype deployment or GPG signing. All three must be set together — if any one is missing, the publishing configuration is skipped entirely:

| Variable | Description |
| :--- | :--- |
| `SONATYPE_USERNAME` | Sonatype / Maven Central username |
| `SONATYPE_PASSWORD` | Sonatype / Maven Central password or token |
| `PGP_PASSPHRASE` | GPG signing passphrase |

### Usage Examples

**Standard library (no scripted tests):**

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: actions/setup-java@v4
    with:
      distribution: 'temurin'
      java-version: '21'

  - name: Setup Global Akka Resolver
    uses: akka/github-actions-scripts/setup_global_resolver@main
```

**sbt plugin project (enables scripted test resolver setup):**

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: actions/setup-java@v4
    with:
      distribution: 'temurin'
      java-version: '21'

  - name: Setup Global Akka Resolver
    uses: akka/github-actions-scripts/setup_global_resolver@main
    with:
      sbt-plugin-project-name: 'my-sbt-plugin'
```

**Project using `protoc` (disables Maven mirrors):**

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: actions/setup-java@v4
    with:
      distribution: 'temurin'
      java-version: '21'

  - name: Setup Global Akka Resolver
    uses: akka/github-actions-scripts/setup_global_resolver@main
    with:
      maven-mirror-control: 'NO_MIRROR'
```

**Full example with all options and credentials:**

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: actions/setup-java@v4
    with:
      distribution: 'temurin'
      java-version: '21'

  - name: Setup Global Akka Resolver
    uses: akka/github-actions-scripts/setup_global_resolver@main
    with:
      sbt-plugin-project-name: 'my-sbt-plugin'
      maven-mirror-control: 'NO_MIRROR'
    env:
      SONATYPE_USERNAME: ${{ secrets.SONATYPE_USERNAME }}
      SONATYPE_PASSWORD: ${{ secrets.SONATYPE_PASSWORD }}
      PGP_PASSPHRASE: ${{ secrets.PGP_PASSPHRASE }}
```

---

## `verify_pom`

Verifies that checked-in, sbt-generated `pom.xml` files are in sync with the build. Use this to catch dependency changes that were generated but not committed.

### What it does

sbt-generated `*.pom` files change on every build — the version string differs and they carry a `<repositories>` section — which makes them impossible to diff directly. This action normalizes them into a stable form and then fails if the committed copies are out of date:

1. Copies each `*.pom` found in the repo to `generated-poms/<artifact-name>/pom.xml`.
2. Normalizes it — the `<version>` is replaced with a fixed `1.0.0-SNAPSHOT` and the `<repositories>` section is removed — so the file only changes when the dependency structure actually changes.
3. Fails the job if this produces a git diff, which means the committed `generated-poms/` are stale.

### Inputs

None.

### Usage Example

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: actions/setup-java@v4
    with:
      distribution: 'temurin'
      java-version: '21'

  - name: Generate poms
    run: sbt makePom

  - name: Verify poms are in sync
    uses: akka/github-actions-scripts/verify_pom@main
```

### Keeping poms up to date

When this action fails, regenerate the normalized poms and commit them:

```bash
sbt makePom
# normalize the generated poms into generated-poms/
curl -sSL https://github.com/akka/github-actions-scripts/raw/refs/heads/main/pom-organize.sh | bash
git add generated-poms
git commit -m "Update generated poms"
```

---

## `artifact_bom_validation`

Fails the job if any files under `artifact-bom/` have changed, indicating the artifact BOM is out of sync with the sbt build.

### What it does

Checks that the committed `artifact-bom/` directory matches the output of the build's BOM generation. A diff means the dependency set has drifted from what is committed.

### Inputs

None.

### Usage Example

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: actions/setup-java@v4
    with:
      distribution: 'temurin'
      java-version: '21'

  - name: Generate BOM
    run: sbt makeBom

  - name: Validate artifact BOM
    uses: akka/github-actions-scripts/artifact_bom_validation@main
```

### Keeping the BOM up to date

When this action fails, regenerate the BOM and commit it:

```bash
sbt makeBom
git add artifact-bom
git commit -m "Update artifact BOM"
```
