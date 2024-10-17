#!/bin/bash

echo "Running Integration Tests..."

# Example: Run integration tests using a custom Maven profile
mvn verify -Pintegration

test_status=$?

if [ $test_status -eq 0 ]; then
    echo "Integration Tests Passed."
    exit 0
else
    echo "Integration Tests Failed."
    exit 1
fi
