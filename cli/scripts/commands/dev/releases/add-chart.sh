#!/bin/bash
set -eou pipefail

## Header Start

# Current Script
currentScript=${BASH_SOURCE[0]}
currentScriptPath="$( cd "$( dirname "${currentScript}" )" >/dev/null 2>&1 && pwd )"
currentScriptShortPath=$(echo "${currentScriptPath}" | awk '{split($0, a, "/scripts/"); print a[2]}')

# Cluster Config
if [[ ! -z $(find ./cluster-config.yaml 2> /dev/null) ]]; then
    clusterConfigPath=$(echo ./cluster-config.yaml | head -n 1 | xargs realpath 2> /dev/null)
else
    clusterConfigPath=$(eval find ./$(printf "{$(echo %{1..7}q,)}" | sed 's/ /\.\.\//g') -maxdepth 1 -name cluster-config.yaml | head -n 1 | xargs realpath 2> /dev/null) || true
fi
# if [[ -z "${clusterConfigPath}" ]] ; then
#     echo "Stopping ${currentScript}"
#     echo "This script requires to be in a cluster context, but cluster-config.yaml not found in parent directories"
#     exit 0
# fi

# clusterConfigDirPath=$(dirname ${clusterConfigPath} | xargs realpath)
# helmfilePath="${clusterConfigDirPath}/helmfile.yaml"
# tmpFolder="${clusterConfigDirPath}/.kube-core/.tmp"

# Cluster Scripts
if [[ ! -z $(find ${currentScriptPath}/scripts-config.yaml 2> /dev/null) ]]; then
    scriptsConfigPath=$(echo ${currentScriptPath}/scripts-config.yaml | head -n 1 | xargs realpath 2> /dev/null)
else
    scriptsConfigPath=$(eval find "${currentScriptPath}"/$(printf "{$(echo %{1..7}q,)}" | sed 's/ /\.\.\//g') -maxdepth 1 -name scripts-config.yaml | head -n 1 | xargs realpath)
fi
scriptsConfigDirPath=$(dirname ${scriptsConfigPath} | xargs realpath)

defaultClusterConfigPath=${scriptsConfigDirPath}/default-cluster-config.yaml
corePath=$(echo ${scriptsConfigDirPath}/../.. | xargs realpath)
coreTmpFolder="${corePath}/.kube-core/.tmp"

# Loading scripts
eval "$(${scriptsConfigDirPath}/src/includes.sh)"

# # Loading default-cluster-config.yaml
# clusterConfigVars=$(parse_yaml ${defaultClusterConfigPath})
# clusterConfigVars=$(echo "${clusterConfigVars}" | sed "s|\./|${clusterConfigDirPath}/|")
# eval "${clusterConfigVars}"

# # Loading cluster-config.yaml
# clusterConfigVars=$(parse_yaml ${clusterConfigPath})
# clusterConfigVars=$(echo "${clusterConfigVars}" | sed "s|\./|${clusterConfigDirPath}/|")
# eval "${clusterConfigVars}"

# Loading scripts-config.yaml
paths=$(parse_yaml ${scriptsConfigPath})
absolutePaths=$(echo "${paths}" | sed "s|\./|${scriptsConfigDirPath}/|")
eval "${absolutePaths}"

check_requirements
# check_context "${cluster_config_context}"
# check_args "$@"
## Header End


tmpReleasesFolder=${coreTmpFolder}/releases
baseReleasesFolder=${tmpReleasesFolder}/releases/base
mkdir -p ${baseReleasesFolder}

if [ $# -eq 0 ]; then
    # plop --plopfile ${corePath}/cli/plopfile.mjs chart | tee .plop.out.data
    echo "You need to provide arguments: chartRepository, chartName, chartVersion"
    exit
else
    plop --plopfile ${corePath}/cli/plopfile.mjs chart ${@} 2> ${tmpReleasesFolder}/.plop.out.log > ${tmpReleasesFolder}/.plop.out.data
fi


plopOutput=$(cat ${tmpReleasesFolder}/.plop.out.data)

chartRepository=$(echo "${plopOutput}" | jq -r '.chartRepository')
chartName=$(echo "${plopOutput}" | jq -r '.chartName')
chartVersion=$(echo "${plopOutput}" | jq -r '.chartVersion')

chartPath=$(realpath ${baseReleasesFolder})

helm pull --repo ${chartRepository} ${chartName} --untar --untardir ${tmpReleasesFolder}

cp -rf ${tmpReleasesFolder}/${chartName} ${chartPath}

${scripts_dev_releases_build_path} ${chartName}
${scripts_dev_releases_cleanup_path}

echo "Done, you can now use this chart by creating a release in kube-core!"
