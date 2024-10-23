#!/bin/bash

echo "Running Integration Tests..."

# Run the integration tests (involving MySQL, etc.)
./mvnw verify -Dtest=**/MySqlIntegrationTests.java

test_status=$?

if [ $test_status -eq 0 ]; then
    echo "Integration Tests Passed."
    exit 0
else
    echo "Integration Tests Failed."
    exit 1
fi
