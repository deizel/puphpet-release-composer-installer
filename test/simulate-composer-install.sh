#!/usr/bin/env bash

#---------------------------------------------------------------------
usage () {
	cat <<EOT

${0##*/}
    Simulates the operation of the \`composer install\` command using this project.

Usage:
    bin/${0##*/} [-h|-t] [release-project-branch-name]

Options:
    -h Prints this help text.
    -t Enables "testing" mode. Will run without prompts, and will execute a number of "unit tests" on the result afterwards, exiting non-zero on failure.

EOT

	exit 0
}
if [ "$1" = '-h' ]; then
	usage
fi

#---------------------------------------------------------------------
# Use like: `die 127 "message for failure"`
die () {
	rc=$1
	shift
	echo "!!" "$@" >&2
	exit $rc
}


# Define working directories.
BASE_DIR="$( cd -P "$( dirname "$0" )"/.. >/dev/null 2>&1 && pwd )"
TEST_DIR="${BASE_DIR}/test"
TMP_DIR="${BASE_DIR}/tmp"


# Set testing mode.
TEST_MODE=
if [ "$1" = '-t' ]; then
	echo "## Setting test mode ON."
	TEST_MODE="yes"
	shift
fi


# Make sure the ../tmp dir contains a symlink to your working copy of `loadsys/puphpet-release`:
echo "## Checking the symlink to the release project."
RELEASE_PROJECT_SYMLINK="${TMP_DIR}/release-project"

if [ -h "${RELEASE_PROJECT_SYMLINK}" ]; then
	RELEASE_PROJECT_PATH=$(readlink "${RELEASE_PROJECT_SYMLINK}")
elif [ -d "${RELEASE_PROJECT_SYMLINK}" ]; then
	RELEASE_PROJECT_PATH="${RELEASE_PROJECT_SYMLINK}"
elif [ "${TEST_MODE}" ]; then
	echo "!! No symlink to the release project working copy"
	echo "!! is present at \`${RELEASE_PROJECT_SYMLINK}\`."
	echo "!! Please create it."
	exit 1
else
	read -p "  Please provide the path to the release project working copy > " RELEASE_PROJECT_PATH
	ln -s "${RELEASE_PROJECT_PATH}" "${RELEASE_PROJECT_SYMLINK}"
fi


# Set the release project's branch name to use.
if [ "${TEST_MODE}" ]; then
	# In testing mode, just default to master when no arg provided.
	RELEASE_PROJECT_BRANCH=${1:-master}
elif [ -n "$1" ]; then
	RELEASE_PROJECT_BRANCH=$1
else
	read -p "  Please provide the branch name from the release project to use > " RELEASE_PROJECT_BRANCH
fi
echo "## Release project branch name is \`${RELEASE_PROJECT_BRANCH}\`."


# Get the name of the branch that is currently checked out in ../ to use.
INSTALLER_PROJECT_BRANCH=$(cd "${BASE_DIR}" >/dev/null 2>&1; git rev-parse --quiet --abbrev-ref HEAD 2>/dev/null )
echo "## Installer project branch name is \`${INSTALLER_PROJECT_BRANCH}\`."


# Delete all contents from the ../tmp folder, except the .gitkeep file and release-project symlink.
echo "## Purging old files from tmp/ folder."
shopt -s dotglob extglob
(
	cd "${TMP_DIR}"
	rm -rf !(.|..|.gitkeep|release-project)
)


# Copy the testing files from test/ to ../tmp/.
echo "## Populating the tmp/ folder."
shopt -s dotglob
(
	cd "${TEST_DIR}"
	cp -R * "${TMP_DIR}/"
)

shopt -u dotglob extglob


# Write the composer.json file in this test dir to the tmp/ dir, adding branch names obtained earlier.
echo "## Writing customized composer.json file."
sed \
 -e "s|PRCI_BRANCH_NAME|${INSTALLER_PROJECT_BRANCH}|" \
 -e "s|PR_BRANCH_NAME|${RELEASE_PROJECT_BRANCH}|" \
 -e "s|PR_DIRECTORY|${RELEASE_PROJECT_PATH}|" \
 <"${TEST_DIR}/composer.json" \
 >"${TMP_DIR}/composer.json"


# Execute the `composer install` command itself.
echo "## Executing \`composer install\`."
cd "${TMP_DIR}/"
composer install --dev --no-interaction --ignore-platform-reqs


# End the script if test mode is OFF.
if [ -z "${TEST_MODE}" ]; then
	echo "## Done simulating \`composer install\`. Examine the results in \`${TMP_DIR}\`."
	exit 0
fi


# In test mode, check for canary values, exit >0 if any are missing. (We could run this script via travis as a test suite.)
echo "## Executing tests."

grep -qe '^/Vagrantfile$' "${TMP_DIR}/.gitignore" \
 || die 101 ".gitignore missing required '/Vagrantfile' entry."

grep -qe '^/puphpet/$' "${TMP_DIR}/.gitignore" \
 || die 102 ".gitignore missing required '/puphpet/' entry."

[ -d "${TMP_DIR}/puphpet" ] \
 || die 103 "Expected puphpet/ directory is not present."

grep -qe '^canary: "foo"$' "${TMP_DIR}/puphpet/config.yaml" \
 || die 104 "puphpet.yaml file was not properly copied into puphpet/ directory."


echo "## Done testing the results of \`composer install\`. No errors encountered."
exit 0
