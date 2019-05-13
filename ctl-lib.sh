function check_envvars() {
    varlist=$1

    varsnotset="F"

    for v in $varlist; do
        if [ -z "${!v}" ]; then
            echo "Required environment variable $v is not set."
            varsnotset="T"
        fi
    done

    if [ "$varsnotset" = "T" ]; then
        echo ""
        echo "Aborted. Please set up required variables."
        exit 1
    fi
}
