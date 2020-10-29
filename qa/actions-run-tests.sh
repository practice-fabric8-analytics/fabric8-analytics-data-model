#!/usr/bin/bash -ex

#SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"

#pushd "${SCRIPT_DIR}/.." > /dev/null

COVERAGE_THRESHOLD=90

DOCKER_CMD="docker-compose -f docker-compose-tests.yml"

gc() {
  retval=$?

  if [[ $retval -ne 0 ]]; then
    docker ps -a
    echo '============ dynamodb logs ============'
    $DOCKER_CMD logs dynamodb || :
    echo
    echo
    echo '============ gremlin logs ============'
    $DOCKER_CMD logs gremlin-http || :
  fi

  $DOCKER_CMD down -v || :
  exit $retval
}

trap gc EXIT SIGINT

# Run local instances: dynamodb, gremlin, gremlin-http, worker-ingestion, pgsql
function start_services {
    echo "Start Gremlin HTTP and Ingestion Workers ..."
    $DOCKER_CMD down
    $DOCKER_CMD up -d gremlin-http
    sleep 5
    $DOCKER_CMD up -d worker-ingestion
}

echo JAVA_OPTIONS value: "$JAVA_OPTIONS"

start_services
pip install -U pip
pip install -r requirements.txt
pip install pytest-profiling
pip install pytest-cov


PYTHONPATH=$(pwd)
export PYTHONPATH

export BAYESIAN_PGBOUNCER_SERVICE_HOST="localhost"


echo "*****************************************"
echo "*** Cyclomatic complexity measurement ***"
echo "*****************************************"
radon cc -s -a -i venv src

echo "*****************************************"
echo "*** Maintainability Index measurement ***"
echo "*****************************************"
radon mi -s -i venv src

echo "*****************************************"
echo "*** Unit tests ***"
echo "*****************************************"
echo "Check for sanity of the connections..."

if python sanitycheck.py
then
    python populate_schema.py
    py.test --cov=src/ --cov-report=xml --cov-fail-under=$COVERAGE_THRESHOLD -vv -s test/
    codecov --token=3c1d9638-afb6-40e6-85eb-3fb193000d4b
else
    echo "Sanity checks failed"
fi
echo "*****************************************"
echo "*** CI Passed ***"


#popd > /dev/null
