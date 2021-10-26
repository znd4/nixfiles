# Add aliases
. ~/.aliasrc

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/go/bin" ]; then
    PATH="$HOME/go/bin:$PATH"
fi

imp() {
    # get the impersonable service account
    fmt_str=mlops-c
    project_id=$(gcloud projects list --filter="name ~ $fmt_str" --format="value(PROJECT_ID)")
    SERVICE_ACCOUNT=$(
        gcloud iam service-accounts list \
            --project=$project_id \
            --filter="email ~ -developers@" \
            --format="value(email)"
    )

    if [[ -z "${SERVICE_ACCOUNT// /}" ]]; then
        echo "Couldn't find service account" >&2
        return 1
    fi

    # this is how we turn on service account impersonation globally
    gcloud config set auth/impersonate_service_account $SERVICE_ACCOUNT

    echo "Started impersonating $SERVICE_ACCOUNT"
}
unimp() {
    # Undo impersonation
    gcloud config unset auth/impersonate_service_account

    echo "Stopped impersonating"
}

source "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc"
source "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc"

if [ -d "$HOME/.dr-proxy" ]; then
    . ~/.dr-proxy/auto_proxy.sh http://internet.ford.com 83
fi

if [ -z ${HTTP_PROXY+x} ]; then
    unset PIP_INDEX_URL
    git config --global --unset http.proxy
    echo "Removed http.proxy from git settings"
else
    export PIP_INDEX_URL=https://www.nexus.ford.com/repository/Ford_ML_public/simple
    export NO_PROXY=$NO_PROXY,192.168.99.0/24,192.168.39.0/24,192.168.49.0/24,10.96.0.0/12
    git config --global http.proxy $HTTP_PROXY
    git config --global https.proxy $HTTP_PROXY
    echo "added http.proxy to git"
fi

source /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh

. ~/.scripts/rc/.zshrc
