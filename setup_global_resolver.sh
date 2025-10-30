#!/bin/bash

# .github/script.sh: Adds the Akka repository globally for sbt and Maven,
# and conditionally injects deployment credentials for Sonatype Maven Central

# Fail on any error, reference undefined variables, and prevent pipeline failures
set -euo pipefail

# --- Configuration ---
AKKA_RESOLVER_URL='https://repo.akka.io/maven/github_actions'
AKKA_SNAPSHOT_RESOLVER_URL='https://repo.akka.io/maven/snapshots/github_actions'
SBT_RESOLVER_LINE="resolvers += \"Akka library repository\" at \"$AKKA_RESOLVER_URL\"
resolvers += \"Akka snapshot repository\" at \"$AKKA_SNAPSHOT_RESOLVER_URL\""

# ARGUMENT 1: SBT plugin project name (optional, defaults to empty)
SBT_PLUGIN_PROJECT_NAME="${1:-}"

# ARGUMENT 2: Mirror control parameter (optional)
# Determine MAVEN_MIRROR_CONTROL: use $2 if it exists, otherwise check if $1 is the control flag.
MAVEN_MIRROR_CONTROL=""
if [ "$#" -ge 2 ]; then
    MAVEN_MIRROR_CONTROL="${2:-}"
elif [ "$#" -eq 1 ] && [[ "$1" == *"MIRROR"* ]]; then
    # If only one argument and it contains "MIRROR", treat it as the mirror control
    MAVEN_MIRROR_CONTROL="$1"
    SBT_PLUGIN_PROJECT_NAME="" # Clear project name if the single argument was the control
fi
# Note: If $1 is "project-name" and $2 is empty, MAVEN_MIRROR_CONTROL remains empty (default behavior)

# Uses GITHUB_WORKSPACE (set by the runner) or defaults to the current directory if run locally
SBT_SCRIPTED_TESTS_BASE_DIR="${GITHUB_WORKSPACE:-.}/${SBT_PLUGIN_PROJECT_NAME}/src/sbt-test"

# Original Default Mirror Block
DEFAULT_MIRRORS_XML="
  <mirrors>
    <mirror>
      <id>akka-repo-redirect</id>
      <mirrorOf>akka-repository</mirrorOf>
      <url>$AKKA_RESOLVER_URL</url>
    </mirror>
    <mirror>
      <mirrorOf>external:http:*</mirrorOf>
      <name>Pseudo repository to mirror external repositories initially using HTTP.</name>
      <url>http://0.0.0.0/</url>
      <blocked>true</blocked>
      <id>maven-default-http-blocker</id>
    </mirror>
    <mirror>
      <id>central</id>
      <mirrorOf>central</mirrorOf>
      <url>https://repo.maven.apache.org/maven2/</url>
    </mirror>
  </mirrors>"

# ----------------------------------------

## Setup for sbt
setup_sbt() {
    echo "--- Setting up Akka resolver for sbt global configuration (~/.sbt/1.0/resolvers.sbt)"
    mkdir -p ~/.sbt/1.0
    echo "$SBT_RESOLVER_LINE" >> ~/.sbt/1.0/resolvers.sbt
    echo "✅ Added resolver to ~/.sbt/1.0/resolvers.sbt"
}

## Setup for Scripted Tests
setup_scripted_tests() {
    echo -e "\n--- Setting up Akka resolver for sbt scripted tests (globally per test case)"

    if [ -z "$SBT_PLUGIN_PROJECT_NAME" ]; then
        echo "⏩ Skipping scripted test setup: SBT plugin project name is empty."
        return 0
    fi
    
    if [ ! -d "$SBT_SCRIPTED_TESTS_BASE_DIR" ]; then
        echo "⚠️ Warning: Tests directory not found: $SBT_SCRIPTED_TESTS_BASE_DIR. Skipping setup for scripted tests."
        return 0
    fi

    echo "Scanning for sbt projects (directories with 'build.sbt') in sbt-tests: $SBT_SCRIPTED_TESTS_BASE_DIR"

    # Use find to recursively locate all 'build.sbt' files.
    find "$SBT_SCRIPTED_TESTS_BASE_DIR" -type f -name 'build.sbt' | while IFS= read -r BUILD_FILE_PATH; do
        PROJECT_ROOT_DIR=$(dirname "$BUILD_FILE_PATH")
        TARGET_DIR="${PROJECT_ROOT_DIR}/global"
        RESOLVERS_FILE="${TARGET_DIR}/resolvers.sbt"

        mkdir -p "$TARGET_DIR"
        echo "$SBT_RESOLVER_LINE" > "$RESOLVERS_FILE"
        echo "-> Configured resolver for project: $PROJECT_ROOT_DIR"
    done
    echo "✅ Finished setting up resolvers for sbt scripted tests."
}

## Setup for Maven
setup_maven() {
    echo -e "\n--- Setting up Akka resolver for Maven global configuration (~/.m2/settings.xml)"
    mkdir -p ~/.m2

    # 1. Define credential variables from environment variables (standard CI practice)
    SONATYPE_USERNAME="${SONATYPE_USERNAME:-}"
    SONATYPE_PASSWORD="${SONATYPE_PASSWORD:-}"
    PGP_PASSPHRASE="${PGP_PASSPHRASE:-}"
    PUBLISH_SERVERS_XML=""
    GPG_PROPERTIES_XML=""
    if [[ -n "$SONATYPE_USERNAME" && -n "$SONATYPE_PASSWORD" && -n "$PGP_PASSPHRASE" ]]; then
        echo "🔑 Publishing credentials found. Injecting servers and GPG passphrase into settings.xml."
        PUBLISH_SERVERS_XML="
  <servers>
    <server>
      <id>central</id>
      <username>${SONATYPE_USERNAME}</username>
      <password>${SONATYPE_PASSWORD}</password>
    </server>
  </servers>"
        GPG_PROPERTIES_XML="
      <properties>
        <gpg.passphrase>${PGP_PASSPHRASE}</gpg.passphrase>
      </properties>"
    else
        echo "⚠️ Publishing credentials (SONATYPE_USERNAME, SONATYPE_PASSWORD, PGP_PASSPHRASE) not set. Skipping publishing configuration."
    fi
    
    # 2. Conditionally define the MIRRORS_XML block
    MIRRORS_XML=""
    if [[ "$MAVEN_MIRROR_CONTROL" != "NO_MIRROR" ]]; then
        echo "🛠️ Including original default mirrors as 'NO_MIRROR' flag was not set."
        MIRRORS_XML="${DEFAULT_MIRRORS_XML}"
    else
        echo "⏩ Skipping all mirrors as requested by parameter: $MAVEN_MIRROR_CONTROL"
        # Since MIRRORS_XML is empty, the <mirrors> tag will be omitted from settings.xml
    fi

    # 3. Generate the full settings.xml file, substituting the dynamic blocks
    cat > ~/.m2/settings.xml <<EOF
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
                      https://maven.apache.org/xsd/settings-1.0.0.xsd">
  
  ${MIRRORS_XML}
  ${PUBLISH_SERVERS_XML}

  <profiles>
    <profile>
      <id>akka-repo</id>
      <repositories>
        <repository>
          <id>akka-repository</id>
          <url>$AKKA_RESOLVER_URL</url>
        </repository>
        <repository>
          <id>akka-snapshots-repository</id>
          <url>$AKKA_SNAPSHOT_RESOLVER_URL</url>
        </repository>
      </repositories>
      
      <pluginRepositories>
        <pluginRepository>
          <id>akka-plugin-repository</id>
          <url>$AKKA_RESOLVER_URL</url>
        </pluginRepository>
        <pluginRepository>
          <id>akka-snapshots-plugin-repository</id>
          <url>$AKKA_SNAPSHOT_RESOLVER_URL</url>
          <snapshots>
            <enabled>true</enabled>
            <updatePolicy>never</updatePolicy> 
          </snapshots>
        </pluginRepository>
      </pluginRepositories>

      ${GPG_PROPERTIES_XML}      
    </profile>
  </profiles>

  <activeProfiles>
    <activeProfile>akka-repo</activeProfile>
  </activeProfiles>
</settings>
EOF
    echo "✅ Created/Overwrote ~/.m2/settings.xml with Akka repository and optional publishing configuration."
}

# --- Main Execution ---
main() {
    setup_sbt
    
    # Check if the project name is set to run scripted tests
    if [ -n "$SBT_PLUGIN_PROJECT_NAME" ]; then
        echo "Using SBT plugin project name: $SBT_PLUGIN_PROJECT_NAME to locate scripted tests."
        setup_scripted_tests
    else
        echo "⚠️ SBT plugin project name (argument \$1) is empty. Skipping scripted test setup."
    fi
    
    setup_maven
    echo -e "\n🎉 Akka resolvers setup complete."
}

main
