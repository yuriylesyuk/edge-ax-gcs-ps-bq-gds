
# remove all artifacts assossiated with the project
set +e
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

$BASEDIR/ctl-gcspsbq.sh nukeitout

$BASEDIR/ctl-edge.sh nukeitout
