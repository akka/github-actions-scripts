# Script Definitions

## Setup Global Resolver Script

This script is a utility designed for CI/CD environments (primarily GitHub Actions) to globally configure **sbt, Maven, and Gradle** to use the Akka repository. This ensures that dependencies hosted by Akka can be resolved without modifying individual project source files.
It automates the setup of repository resolvers and deployment credentials across multiple build systems with primary goals of:
* **Global Dependency Resolution:** Injects Akka Release and Snapshot URLs into global config files.
* **Credential Injection:** Dynamically sets up Sonatype Maven Central deployment credentials if environment variables are present.
* **Security:** Configures a Maven HTTP blocker to prevent insecure repository connections.
* **Test Isolation:** Specifically configures sbt "scripted" tests for plugin development.

---

### Script Parameters

The script accepts two positional arguments. It includes logic to handle cases where only one argument is provided.

| Parameter | Position | Required | Description |
| :--- | :--- | :--- | :--- |
| **SBT Project Name** | `$1` | No | The name of the sbt plugin project directory. Used to locate `src/sbt-test` for scripted test setup. |
| **Mirror Control** | `$2` | No | Set to `NO_MIRROR` to prevent the script from injecting `<mirrors>` into the Maven `settings.xml`. |

#### Argument Logic
* **If 2 arguments are provided:** `$1` is the project name, `$2` is the mirror control.
* **If 1 argument is provided and it contains "MIRROR":** The script treats it as the mirror control flag and leaves the project name empty.
* **If 1 argument is provided and it does NOT contain "MIRROR":** It is treated as the sbt project name.

---

### Environment Variables

The script utilizes the following environment variables for advanced configuration:

* `SONATYPE_USERNAME`: The username for Sonatype/Maven Central.
* `SONATYPE_PASSWORD`: The password/token for Sonatype/Maven Central.
* `PGP_PASSPHRASE`: The passphrase used for GPG signing of artifacts.

---

### Usage Examples

The general format for use in Github Actions is:

```
      - name: Checkout Global Scripts
        uses: actions/checkout@v4
        with:
          repository: akka/github-actions-scripts
          path: scripts
          fetch-depth: 0

      - name: Setup global resolver
        run: |
          chmod +x ./scripts/setup_global_resolver.sh
          ./scripts/setup_global_resolver.sh
```

Then the specific use of the shell would look like the followin

**Standard usage for a library (No scripted tests):**
```bash
./scripts/setup_global_resolver.sh
```

**Usage for an sbt plugin (Enables scripted test setup):**
```bash
./scripts/setup_global_resolver.sh sbt-plugin
```

**Usage where Maven mirrors must be disabled:**
```bash
./scripts/setup_global_resolver.sh NO_MIRROR
```

---

### Key Functions

#### `setup_sbt()`
Creates or appends to `~/.sbt/1.0/resolvers.sbt`. It adds the Akka release and snapshot URLs as global resolvers for all sbt builds on the machine.

#### `setup_scripted_tests()`
If a project name is provided, the script searches for `build.sbt` files within the `sbt-test` directory. It then creates a `global/resolvers.sbt` file for **every** individual test case found. This is critical for sbt plugin testing where each test case runs in an isolated environment.

#### `setup_gradle()`
Generates a Gradle Init Script at `~/.gradle/init.d/akka-resolvers.init.gradle`. This uses the `allprojects` block to inject the Akka Maven repositories into both the `buildscript` (for plugins) and the standard `repositories` (for dependencies).

#### `setup_maven()`
Generates a `~/.m2/settings.xml` file with:
* **Mirrors:** Blocks all plain `http` traffic for security and redirects Akka requests.
* **Profiles:** Creates an `akka-repo` profile and sets it to `<activeByDefault>`.
* **Credentials:** If Sonatype variables are found, it injects `<servers>` and GPG properties into the settings file.


