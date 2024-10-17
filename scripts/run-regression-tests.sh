#!/bin/bash

echo "Running Regression Tests..."

# Example: Run all regression tests (JUnit tests)
mvn test -Dtest=com.example.RegressionTestSuite

test_status=$?

if [ $test_status -eq 0 ]; then
    echo "Regression Tests Passed."
    exit 0
else
    echo "Regression Tests Failed."
    exit 1
fi
