#!/bin/bash

# ==============================================================================
# SonarQube Project Lines of Code Reporter
#
# Description:
# This script retrieves a list of all projects from a SonarQube server
# and then fetches the value for a specific metric (default: ncloc,
# non-commenting lines of code) for each project.
#
# Dependencies:
# - curl: A command-line tool for transferring data with URLs.
# - jq: A lightweight and flexible command-line JSON processor.
#
# Usage:
# 1. Set SONAR_URL and SONAR_TOKEN as environment variables.
# 3. Make the script executable: chmod +x your_script_name.sh
# 4. Run the script: ./your_script_name.sh
# ==============================================================================

# --- Configuration ---
# REQUIRED: Your SonarQube server URL (e.g., http://localhost:9000)
# export SONAR_URL="YOUR_SONARQUBE_URL"

# REQUIRED: Your SonarQube authentication token.
# Generate one from My Account > Security in the SonarQube UI.
# export SONAR_TOKEN="YOUR_SONAR_TOKEN"

# The metric you want to retrieve. 'ncloc' is "Non-Commenting Lines of Code".
# Other examples: 'bugs', 'vulnerabilities', 'coverage', 'duplicated_lines_density'
METRIC_TO_GET="ncloc"

# --- Script Body ---

# 1. Check for dependencies
# We need 'jq' to parse the JSON responses from the API.
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed, but it's required to run this script." >&2
    echo "On Debian/Ubuntu: sudo apt-get install jq" >&2
    echo "On RedHat/CentOS: sudo yum install jq" >&2
    echo "On macOS (with Homebrew): brew install jq" >&2
    exit 1
fi

# We also need curl, though it's almost always available.
if ! command -v curl &> /dev/null; then
    echo "Error: 'curl' is not installed. Please install it to run this script." >&2
    exit 1
fi

# 2. Validate that the user has updated the placeholder configuration
if [[ "$SONAR_URL" == "YOUR_SONARQUBE_URL" ]] || [[ -z "$SONAR_URL" ]]; then
    echo "Error: Please edit the script and set your SonarQube URL in the SONAR_URL variable." >&2
    exit 1
fi

if [[ "$SONAR_TOKEN" == "YOUR_SONAR_TOKEN" ]] || [[ -z "$SONAR_TOKEN" ]]; then
    echo "Error: Please edit the script and set your SonarQube authentication token in the SONAR_TOKEN variable." >&2
    exit 1
fi

echo "Fetching all projects from SonarQube instance at $SONAR_URL..."

# 3. Get all project keys from the SonarQube API, handling pagination
PAGE=1
PAGE_SIZE=100 # The API's page size can be up to 500
ALL_PROJECT_KEYS=() # Use an array to store all project keys

while true; do
    # Use curl to call the projects/search API.
    # The '-s' flag makes curl silent, and '-u' provides the auth token.
    PROJECTS_RESPONSE=$(curl -s -u "${SONAR_TOKEN}:" "${SONAR_URL}/api/projects/search?p=${PAGE}&ps=${PAGE_SIZE}")
    echo $PROJECTS_RESPONSE
    # Use jq to parse the JSON and extract the 'key' for each component.
    # The '-r' flag gives raw string output without quotes.
    # We read the results into an array.
    PROJECTS_ON_PAGE=($(echo "$PROJECTS_RESPONSE" | jq -r '.components[].key'))

    # If the array of projects for the current page is empty, we've fetched all pages.
    if [ ${#PROJECTS_ON_PAGE[@]} -eq 0 ]; then
        break
    fi

    # Add the keys from this page to our main list of all keys.
    ALL_PROJECT_KEYS+=("${PROJECTS_ON_PAGE[@]}")

    # Increment the page number to fetch the next set of results in the next loop.
    ((PAGE++))
done

# Check if we found any projects at all.
if [ ${#ALL_PROJECT_KEYS[@]} -eq 0 ]; then
    echo "Warning: No projects were found on the SonarQube server."
    exit 0
fi

echo "Found ${#ALL_PROJECT_KEYS[@]} projects. Now fetching the '${METRIC_TO_GET}' measure for each..."
echo "---------------------------------------------------------------------"

# 4. Loop through each project key and get the specified metric
for PROJECT_KEY in "${ALL_PROJECT_KEYS[@]}"; do
    # Make the API call to get the measures for the specific project (component).
    MEASURE_RESPONSE=$(curl -s -u "${SONAR_TOKEN}:" "${SONAR_URL}/api/measures/component?component=${PROJECT_KEY}&metricKeys=${METRIC_TO_GET}")

    # Parse the JSON response to get the value of the metric.
    # The `// "N/A"` part in jq provides a default value if the path doesn't exist,
    # which can happen if a project hasn't had this measure computed.
    METRIC_VALUE=$(echo "$MEASURE_RESPONSE" | jq -r ".component.measures[0].value // \"N/A\"")

    # Print the result in a nicely formatted table-like structure.
    printf "Project: %-50s | %s: %s\n" "$PROJECT_KEY" "$METRIC_TO_GET" "$METRIC_VALUE"
done

echo "---------------------------------------------------------------------"
echo "Script finished."
