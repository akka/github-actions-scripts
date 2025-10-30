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

# ARGUMENT 2: Mirror control parameter (optional, defaults to empty)
# Use shift to promote the second argument to $1 if $1 was not provided, 
# or just reference $2 if $1 was provided. This is robust in the next function.

# The script logic below will access the mirror control as ${2:-} if $1 is passed,
# or as ${1:-} if $1 is NOT passed and we use $2 instead. 
# A cleaner way is to simply check for the argument explicitly:
if [ "$#" -ge 2 ]; then
    MAVEN_MIRROR_CONTROL="${2:-}"
else
    # If only one argument is provided, check if it's the mirror control value
    # by checking if it contains "MIRROR" (a heuristic, but simple for this case)
    if [[ "$1" == *"MIRROR"* ]]; then
        MAVEN_MIRROR_CONTROL="${1:-}"
    else
        MAVEN_MIRROR_CONTROL=""
    fi
fi
# Simpler alternative: assume the mirror control is always the LAST argument passed, 
# and the sbt project name is the FIRST argument passed (even if empty).

# For simplicity and clarity in the final function, let's explicitly define how 
# the mirror control argument is determined, supporting an empty first argument.

# If the script is called with one argument, and that argument is "NO_MIRROR", 
# we set SBT_PLUGIN_PROJECT_NAME to empty and MAVEN_MIRROR_CONTROL to "NO_MIRROR".
if [ "$#" -eq 1 ] && [[ "$1" == *"MIRROR"* ]]; then
    MAVEN_MIRROR_CONTROL="$1"
    SBT_PLUGIN_PROJECT_NAME=""
else
    # Standard assignment: $1 for project name, $2 for mirror control
    SBT_PLUGIN_PROJECT_NAME="${1:-}"
    MAVEN_MIRROR_CONTROL="${2:-}"
fi

# Uses GITHUB_WORKSPACE (set by the runner) or defaults to the current directory if run locally
SBT_SCRIPTED_TESTS_BASE_DIR="${GITHUB_WORKSPACE:-.}/${SBT_PLUGIN_PROJECT_NAME}/src/sbt-test"

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

    # Skip if project name is empty (i.e., user intentionally skipped $1)
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
    
    # 2. Conditionally define the MIRROR_BLOCKER_XML block
    MIRROR_BLOCKER_XML=""
    if [[ "$MAVEN_MIRROR_CONTROL" != "NO_MIRROR" ]]; then
        echo "🛠️ Including default '*' mirror configuration to satisfy protoc-jar's custom lookup."
        MIRROR_BLOCKER_XML="
    <mirror>
      <mirrorOf>*</mirrorOf>
      <name>Pseudo repository for protoc-jar compatibility</name>
      <url>https://repo.maven.apache.org/maven2/</url> 
      <id>central-mirror-for-protoc</id>
    </mirror>"
    else
        echo "⏩ Skipping '*' mirror configuration as requested by parameter: $MAVEN_MIRROR_CONTROL"
    fi

    # 3. Generate the full settings.xml file, substituting the dynamic blocks
    cat > ~/.m2/settings.xml <<EOF
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
                      https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <mirrors>
    <mirror>
      <id>akka-repo-redirect</id>
      <mirrorOf>akka-repository</mirrorOf>
      <url>$AKKA_RESOLVER_URL</url>
    </mirror>
    
    ${MIRROR_BLOCKER_XML}
    <mirror>
      <mirrorOf>external:http:*</mirrorOf>
      <name>Pseudo repository to mirror external repositories initially using HTTP.</name>
      <url>http://0.0.0.0/</url>
      <blocked>true</blocked>
      <id>maven-default-http-blocker</id>
    </mirror>
  </mirrors>
  
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
