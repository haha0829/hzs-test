#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help                Display help
    -t, --type                Operation type
                                1) remove v prefix
                                2) replace '-' with '.'
                                3) get release asset upload url
                                4) update release latest
                                5) update release latest
                                6) get the ci trigger mode
                                7) check image exists
                                8) check package version
                                9) trigger release
                                11) release message
                                12) send message
                                13) delete docker images
                                14) delete aliyun images
    -tn, --tag-name           Release tag name
    -gr, --github-repo        Github Repo
    -gt, --github-token       Github token
    -bn, --branch-name        The branch name
    -c, --content             The trigger request content
    -bw, --bot-webhook        The bot webhook
    -tt, --trigger-type       The trigger type (e.g. release/package)
    -ru, --run-url            The run url
EOF
}

GITHUB_API="https://api.github.com"
LATEST_REPO=JashBook/hzs-test

main() {
    local TYPE
    local TAG_NAME
    local GITHUB_REPO
    local GITHUB_TOKEN
    local TRIGGER_MODE=""
    local EXIT_STATUS=0
    local BRANCH_NAME=""
    local CONTENT=""
    local BOT_WEBHOOK=""
    local TRIGGER_TYPE=""
    local RELEASE_VERSION=""
    local RUN_URL=""
    local USER=""
    local PASSWORD=""

    parse_command_line "$@"

    local TAG_NAME_TMP=${TAG_NAME/v/}

    case $TYPE in
        1)
            echo "${TAG_NAME/v/}"
        ;;
        2)
            echo "${TAG_NAME/-/.}"
        ;;
        3)
            get_upload_url
        ;;
        4)
            get_latest_tag
        ;;
        5)
            update_release_latest
        ;;
        6)
            get_trigger_mode
        ;;
        7)
            check_image_exists
        ;;
        8)
            check_package_version
        ;;
        9)
            trigger_release
        ;;
        11)
            release_message
        ;;
        12)
            send_message
        ;;
        13)
            delete_docker_images
        ;;
        14)
            delete_aliyun_images
        ;;
        *)
            show_help
            break
        ;;
    esac
    echo $EXIT_STATUS
    exit $EXIT_STATUS
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
                ;;
            -t|--type)
                if [[ -n "${2:-}" ]]; then
                    TYPE="$2"
                    shift
                fi
                ;;
            -tn|--tag-name)
                if [[ -n "${2:-}" ]]; then
                    TAG_NAME="$2"
                    shift
                fi
                ;;
            -gr|--github-repo)
                if [[ -n "${2:-}" ]]; then
                    GITHUB_REPO="$2"
                    shift
                fi
                ;;
            -gt|--github-token)
                if [[ -n "${2:-}" ]]; then
                    GITHUB_TOKEN="$2"
                    shift
                fi
                ;;
            -bn|--branch-name)
                if [[ -n "${2:-}" ]]; then
                    BRANCH_NAME="$2"
                    shift
                fi
                ;;
            -c|--content)
                if [[ -n "${2:-}" ]]; then
                    CONTENT="$2"
                    shift
                fi
                ;;
            -bw|--bot-webhook)
                if [[ -n "${2:-}" ]]; then
                    BOT_WEBHOOK="$2"
                    shift
                fi
                ;;
            -tt|--trigger-type )
                if [[ -n "${2:-}" ]]; then
                    TRIGGER_TYPE="$2"
                    shift
                fi
                ;;
            -ru|--run-url)
                if [[ -n "${2:-}" ]]; then
                    RUN_URL="$2"
                    shift
                fi
                ;;
            -u|--user)
                if [[ -n "${2:-}" ]]; then
                    USER="$2"
                    shift
                fi
                ;;
            -p|--password)
                if [[ -n "${2:-}" ]]; then
                    PASSWORD="$2"
                    shift
                fi
                ;;
            *)
                break
                ;;
        esac

        shift
    done
}

gh_curl() {
    curl -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3.raw" \
      $@
}

get_upload_url() {
    gh_curl -s $GITHUB_API/repos/$GITHUB_REPO/releases/tags/$TAG_NAME > release_body.json
    echo $(jq '.upload_url' release_body.json) | sed 's/\"//g'
}

update_release_latest() {
    latest_release_tag=`gh_curl -s $GITHUB_API/repos/$LATEST_REPO/releases/latest | jq -r '.tag_name'`

    release_id=`gh_curl -s $GITHUB_API/repos/$GITHUB_REPO/releases/tags/$latest_release_tag | jq -r '.id'`

    gh_curl -X PATCH \
        $GITHUB_API/repos/$GITHUB_REPO/releases/$release_id \
        -d '{"draft":false,"prerelease":false,"make_latest":true}'
}

add_trigger_mode() {
    trigger_mode=$1
    if [[ "$TRIGGER_MODE" != *"$trigger_mode"* ]]; then
        TRIGGER_MODE="["$trigger_mode"]"$TRIGGER_MODE
    fi
}

get_trigger_mode() {
    for filePath in $( git diff --name-only HEAD HEAD^ ); do

        if [[ "$filePath" == "go."* || "$filePath" == "Makefile" ]]; then
            add_trigger_mode "test"
            break
        elif [[ "$filePath" != *"/"* ]]; then
          echo $filePath
            add_trigger_mode "other"
            continue
        fi

        case $filePath in
            docs/*)
                add_trigger_mode "docs"
            ;;
            docker/*)
                add_trigger_mode "docker"
            ;;
            deploy/*)
                add_trigger_mode "deploy"
            ;;
            .github/*|.devcontainer/*|githooks/*|examples/*)
                add_trigger_mode "other"
            ;;
            *)
                add_trigger_mode "test"
                break
            ;;
        esac
    done
    echo $TRIGGER_MODE
}



check_numeric() {
    input=${1:-""}
    if [[ $input =~ ^[0-9]+$ ]]; then
        echo $(( ${input} ))
    else
        echo "no"
    fi
}

get_next_available_tag() {
    tag_type="$1"
    index=""
    release_list=$( gh release list --repo $LATEST_REPO )
    for tag in $( echo "$release_list" | (grep "$tag_type" || true) ) ;do
        if [[ "$tag" != "$tag_type"* ]]; then
            continue
        fi
        tmp=${tag#*$tag_type}
        numeric=$( check_numeric "$tmp" )
        if [[ "$numeric" == "no" ]]; then
            continue
        fi
        if [[ $numeric -gt $index ]]; then
            index=$numeric
        fi
    done

    if [[ -z "$index" ]];then
        index=0
    else
        index=$(( $index + 1 ))
    fi

    RELEASE_VERSION="${tag_type}${index}"
}

release_next_available_tag() {
    dispatches_url=$1
    v_head="v$TAG_NAME"
    alpha_type="$v_head.0-alpha."
    beta_type="$v_head.0-beta."
    rc_type="$v_head.0-rc."
    stable_type="$v_head."
    case "$CONTENT" in
        *alpha*)
            get_next_available_tag "$alpha_type"
        ;;
        *beta*)
            get_next_available_tag "$beta_type"
        ;;
        *rc*)
            get_next_available_tag "$rc_type"
        ;;
        *stable*)
            get_next_available_tag $stable_type
        ;;
    esac

    if [[ ! -z "$RELEASE_VERSION" ]];then
        gh_curl -X POST $dispatches_url -d '{"ref":"'$BRANCH_NAME'","inputs":{"release_version":"'$RELEASE_VERSION'"}}'
    fi
}

usage_message() {
    curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
        -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Usage:","content":[[{"tag":"text","text":"sorry master, please enter the correct format\n"},{"tag":"text","text":"1. do <alpha|beta|rc|stable> release\n"},{"tag":"text","text":"2. {\"ref\":\"<ref_branch>\",\"inputs\":{\"release_version\":\"<release_version>\"}}"}]]}}}}'
}

trigger_release() {
    echo "CONTENT:$CONTENT"
    dispatches_url=$GITHUB_API/repos/$LATEST_REPO/actions/workflows/$TRIGGER_TYPE-version.yml/dispatches

    if [[ "$CONTENT" == "do"*"release" ]]; then
        release_next_available_tag "$dispatches_url"
    else
        usage_message
    fi
}

release_message() {
    curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
        -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Release:","content":[[{"tag":"text","text":"yes master, release "},{"tag":"a","text":"['$TAG_NAME']","href":"https://github.com/'$LATEST_REPO'/releases/tag/'$TAG_NAME'"},{"tag":"text","text":" is on its way..."}]]}}}}'
}

send_message() {
    if [[ "$CONTENT" == *"success" ]]; then
        curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
            -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Success:","content":[[{"tag":"text","text":"'$CONTENT'"}]]}}}}'
    else
        curl -H "Content-Type: application/json" -X POST $BOT_WEBHOOK \
            -d '{"msg_type":"post","content":{"post":{"zh_cn":{"title":"Error:","content":[[{"tag":"text","text":"sorry master, "},{"tag":"a","text":"['$CONTENT']","href":"'$RUN_URL'"}]]}}}}'
    fi
}

check_image_exists() {
     image=registry.cn-hangzhou.aliyuncs.com/apecloud/configmap-reload:v0.5.0
    for i in {1..5}; do
        architectures=$( docker manifest inspect "$image" | grep architecture )
        if [[ -z "$architectures" ]]; then
            if [[ $i -lt 5 ]]; then
                sleep 1
                continue
            fi
        else
            if [[ "$architectures" != *"amd64"* ]];then
                echo "::error title=Missing Amd64 Arch::$image missing amd64 architecture"
                EXIT_STATUS=1
            elif [[ "$architectures" != *"arm641"* ]]; then
                echo "::error title=Missing Arm64 Arch::$image missing arm64 architecture"
                EXIT_STATUS=1
            else
                echo "$image found amd64/arm64 architecture"
            fi
            break
        fi
        echo "$(tput setaf 1)$image is not exists.$(tput sgr 0)"
#        EXIT_STATUS=1
    done
}

check_package_version() {
    exit_status=0
    beta_tag="v"*"."*"."*"-beta."*
    rc_tag="v"*"."*"."*"-rc."*
    official_tag="v"*"."*"."*
    not_official_tag="v"*"."*"."*"-"*
    if [[ "$TAG_NAME" == $official_tag && "$TAG_NAME" != $not_official_tag ]]; then
        echo "::error title=Release Version Not Allow::$(tput -T xterm setaf 1) $TAG_NAME does not allow packaging.$(tput -T xterm sgr0)"
        exit_status=1
    elif [[ "$TAG_NAME" == $beta_tag ]]; then
        echo "::error title=Beta Version Not Allow::$(tput -T xterm setaf 1) $TAG_NAME does not allow packaging.$(tput -T xterm sgr0)"
        exit_status=1
    elif [[ "$TAG_NAME" == $rc_tag ]]; then
        echo "::error title=Release Candidate Version Not Allow::$(tput -T xterm setaf 1) $TAG_NAME does not allow packaging.$(tput -T xterm sgr0)"
        exit_status=1
    else
        echo "$(tput -T xterm setaf 2)Version allows packaging$(tput -T xterm sgr0)"
    fi
    exit $exit_status
}

delete_docker_images() {
    echo "delete kubeblocks image $TAG_NAME_TMP"
    docker run --rm -it apecloud/remove-dockerhub-tag \
        --user "$USER" --password "$PASSWORD" \
        apecloud/kubeblocks:$TAG_NAME_TMP

    echo "delete kubeblocks-tools image $TAG_NAME_TMP"
    docker run --rm -it apecloud/remove-dockerhub-tag \
        --user "$USER" --password "$PASSWORD" \
        apecloud/kubeblocks-tools:$TAG_NAME_TMP
}

delete_aliyun_images() {
    echo "delete kubeblocks image $TAG_NAME_TMP"
    skopeo delete docker://registry.cn-hangzhou.aliyuncs.com/apecloud/kubeblocks:$TAG_NAME_TMP \
        --creds "$USER:$PASSWORD"

    echo "delete kubeblocks-tools image $TAG_NAME_TMP"
    skopeo delete docker://registry.cn-hangzhou.aliyuncs.com/apecloud/kubeblocks-tools:$TAG_NAME_TMP \
        --creds "$USER:$PASSWORD"
}

main "$@"
