#!/usr/bin/env bash

set -e

PCK_PREFIX=${PCK_PREFIX:-~/.local/bin}

PCK_CACHE_DIR=${PCK_CACHE_DIR:-~/.cache/pck}

if [[ $PCK_DEV ]]; then
    . functions
else
    error() { echo "Error: $*" >&2; exit 1; }

    command -v curl >/dev/null || error "Command required: curl"

    functions=$(curl -sfS https://raw.githubusercontent.com/mtherreault/blib/pck/functions) || error "Failed downloading bootstrap functions"

    source <(echo "$functions")
fi

function usage {
    cat <<END
Install scripts from target into install directory.

When target file is a directory, all declared targets are installed.

Usage:
  $0 [options] <target> ...

Install target can be a Git repository:
    git@github.com:kubernetes/kubernetes.git/hack/lib/util.sh (latest semver)
    ssh://git@github.com:kubernetes/kubernetes.git/hack/lib/util.sh@v1.22.0
    https://github.com/kubernetes/kubernetes.git/hack/lib/util.sh@master
An URL:
    https://raw.githubusercontent.com/mtherreault/blib/pck/functions
    ssh://user@host.net:22/workspace/src/crm/cli
    file:///pkg/tool/script
Or a file:
    ../lib/net-util.sh
    /opt/admin/tools/k8s/

Options:
  --prefix, -p <PATH>
    Install destination directory (PCK_PREFIX=$PCK_PREFIX)
  --confirm, -c
    Ask overwrite confirmation when destination exists
END
    exit 2
}

confirm=

while [[ $# -gt 0 ]]; do
case $1 in
--prefix | -p)
    PCK_PREFIX=$2
    shift 2 || usage
    ;;
--confirm | -c)
    confirm=confirm
    shift
    ;;
--help | -h)
    usage
    ;;
--)
    shift
    break
    ;;
-?*)
    error "Unknown option: $1"
    ;;
*)
    break
    ;;
esac
done

[[ $# -gt 0 ]] || usage

targets=()

declare -A target=(); struct_new target url repo path handler

function load_target {
    local spec=$1

    local url=$spec scheme auth user host relative path segments=()

    if [[ $url =~ ^[[:alpha:]][[:alnum:]+.-]*:// ]]; then
        scheme=${BASH_REMATCH:0:-3}
        scheme=${scheme,,}
        url=${url:${#BASH_REMATCH}}
    elif [[ $url =~ ^\.{0,2}/ ]]; then
        scheme=file
        [[ $url == .* ]] && relative=_
    elif [[ $url =~ ^[[:alnum:]]+(-[[:alnum:]]+)*/ ]]; then
        scheme=https
        url=github.com/$url
    elif [[ $url =~ ^[^/?#]+: ]]; then
        scheme=ssh
        url=${BASH_REMATCH:0:-1}/${url:${#BASH_REMATCH}}
    else
        return 1
    fi

    if [[ ! $relative && $url =~ ^[^/?#]+ ]]; then
        auth=$BASH_REMATCH
        url=${url:${#BASH_REMATCH}}

        if [[ $auth =~ ^.+@ ]]; then
            user=${BASH_REMATCH:0:-1}
            host=${auth:${#BASH_REMATCH}}
        else
            host=$auth
        fi

        auth=${host,,}
        [[ $user ]] && auth=$user@$auth
    fi
    [[ $auth && $scheme == file ]] && error "File URL with authority not supported in target: $spec"

    if [[ $url =~ ^[^?#]+ ]]; then
        path=$BASH_REMATCH
        url=${url:${#BASH_REMATCH}}
    fi
    [[ $relative || $path == /* ]] || path=/$path

    array_split__ segments "$path" /+

    #TODO check for git repo

    array_join__ path segments /

    url=$scheme://$auth$path$url

    debug "URL: $url"

    target+=(
        [url]=$url
        [repo]=
        [path]=$path
        [handler]=
    )

    struct_set target "$url"

    targets+=("$url")

    #TODO handle target type? (directory or file)

    #TODO handle relative path to parent

    return 0
}

function install_file {
    local file=$1 dir=$2

    local dest=$dir/$(basename "$file")

    #TODO use install command
    # cp "$file" "$dest"

    # chmod a+x "$dest"

    msg Installed: @green@ "$dest"
}

# The following syntaxes may be used with them:

# ssh://[user@]host.xz[:port]/path/to/repo.git/
# git://host.xz[:port]/path/to/repo.git/
# http[s]://host.xz[:port]/path/to/repo.git/
# ftp[s]://host.xz[:port]/path/to/repo.git/

# An alternative scp-like syntax may also be used with the ssh protocol:

# [user@]host.xz:path/to/repo.git/

# This syntax is only recognized if there are no slashes before the first colon.
# This helps differentiate a local path that contains a colon.
# For example the local path foo:bar could be specified as an absolute path or ./foo:bar to avoid being misinterpreted as an ssh url.

# The ssh and git protocols additionally support ~username expansion:

# ssh://[user@]host.xz[:port]/~[user]/path/to/repo.git/
# git://host.xz[:port]/~[user]/path/to/repo.git/

# [user@]host.xz:/~[user]/path/to/repo.git/

# For local repositories, also supported by Git natively, the following syntaxes may be used:

# /path/to/repo.git/
# file:///path/to/repo.git/

# These two syntaxes are mostly equivalent, except the former implies --local option.

# https://gitlab-ncsa.ubisoft.org/fleet/operators/logging-operator.git
# git@gitlab-ncsa.ubisoft.org:fleet/operators/logging-operator.git

# https://github.com/mtherreault/blib.git
# git@github.com:mtherreault/blib.git

[[ $# -eq 0 ]] && usage

[[ -e $PCK_PREFIX ]] || mkdir -p "$PCK_PREFIX" || error "Failed creating install directory: $PCK_PREFIX"
[[ -d $PCK_PREFIX ]] || error "Invalid install directory: $PCK_PREFIX"

for spec; do
    debug "Loading target: $spec"

    load_target "$spec" || error "Invalid target spec: $spec"
done

for target in "${targets[@]}"; do
    install_file "$target" "$PCK_PREFIX" || error "Failed installing target: $target"
done
