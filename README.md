# github-actions-scripts

A collection of reusable GitHub Actions composite actions for Akka projects.

---

## `setup_global_resolver`

Globally configures **sbt, Maven, and Gradle** to resolve dependencies from the Akka repository. Use this in CI workflows to inject Akka resolvers without modifying individual project source files.

### What it does

- Injects Akka release and snapshot repository URLs into global config files for sbt, Maven, and Gradle
- Optionally configures Sonatype Maven Central deployment credentials from environment variables
- Configures a Maven HTTP blocker to prevent insecure repository connections
- Optionally sets up sbt scripted test resolvers for plugin development

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
| `maven-mirror-control` | No | `''` | Set to `NO_MIRROR` to skip injecting `<mirrors>` into Maven `settings.xml`. Required for projects using `protoc`, which manages its own resolver and does not handle mirrored repositories. |

### Environment Variables

Set these as GitHub Actions secrets/variables if you need Sonatype deployment or GPG signing:

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

  - name: Setup Global Akka Resolver
    uses: akka/github-actions-scripts/setup_global_resolver@main
```

**sbt plugin project (enables scripted test resolver setup):**

```yaml
steps:
  - uses: actions/checkout@v4

  - name: Setup Global Akka Resolver
    uses: akka/github-actions-scripts/setup_global_resolver@main
    with:
      sbt-plugin-project-name: 'my-sbt-plugin'
```

**Project using `protoc` (disables Maven mirrors):**

```yaml
steps:
  - uses: actions/checkout@v4

  - name: Setup Global Akka Resolver
    uses: akka/github-actions-scripts/setup_global_resolver@main
    with:
      maven-mirror-control: 'NO_MIRROR'
```

**Full example with all options and credentials:**

```yaml
steps:
  - uses: actions/checkout@v4

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
