#!/bin/bash

echo "Running Functional Tests..."

# Run unit/functional tests using Maven
./mvnw test -Dtest=**/service/*.java -DfailIfNoTests=false

test_status=$?

if [ $test_status -eq 0 ]; then
    echo "Functional Tests Passed."
    exit 0
else
    echo "Functional Tests Failed."
    exit 1
fi
