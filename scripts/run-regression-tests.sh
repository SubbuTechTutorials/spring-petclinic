#!/bin/bash

echo "Running Regression Tests..."

# Run all tests (typically, regression tests are a broader set)
./mvnw test -Dtest=**/*.java -DfailIfNoTests=false

test_status=$?

if [ $test_status -eq 0 ]; then
    echo "Regression Tests Passed."
    exit 0
else
    echo "Regression Tests Failed."
    exit 1
fi
