#!/bin/bash

echo "Running Regression Tests..."

# Run all tests (without any specific test class pattern)
./mvnw test

# Capture the exit status of the Maven test command
test_status=$?

# Check if tests passed or failed
if [ $test_status -eq 0 ]; then
    echo "Regression Tests Passed."
    exit 0
else
    echo "Regression Tests Failed."
    exit 1
fi
