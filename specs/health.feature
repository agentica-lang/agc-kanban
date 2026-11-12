Feature: Health and API authentication
  Scenario Outline: Public health and protected API
    Given the test server is running
    When I get "<path>" with key "<key>"
    Then the response status is <status>

    Examples:
      | path        | key                              | status |
      | /api/health |                                  | 200    |
      | /api/health | wrong                            | 200    |
      | /api/auth-check |                                  | 401    |
      | /api/auth-check | wrong                            | 401    |
      | /api/auth-check | 01234567890123456789012345678901 | 200    |

  Scenario: Server refuses a short key
    Given the environment variable "KANBAN_API_KEY" is "short"
    And the Agentica program "../server.agc"
    Then the program exits with code 1 within 30000 milliseconds
    And stderr includes:
      """
      KANBAN_API_KEY must be at least 32 characters
      """

  Scenario: Whoami reports an unreachable server
    Given the environment variable "KANBAN_URL" is "http://127.0.0.1:0"
    And the program argument "whoami"
    And the Agentica program "../cli.agc"
    Then the program exits with code 3 within 10000 milliseconds
    And stderr includes:
      """
      kanban:
      """

  Scenario Outline: Whoami checks the API key
    Given the test server is running
    When I run whoami with key "<key>"
    Then whoami exits with code <code>

    Examples:
      | key                              | code |
      |                                  | 3    |
      | wrong                            | 3    |
      | 01234567890123456789012345678901 | 0    |

  Scenario: Whoami rejects an unrelated server
    Given an unrelated server is running
    When I run whoami with key "01234567890123456789012345678901"
    Then whoami exits with code 3

  Scenario: Whoami returns JSON on connection failure
    Given the environment variable "KANBAN_URL" is "http://127.0.0.1:0"
    And the program argument "whoami"
    And the program argument "--json"
    And the Agentica program "../cli.agc"
    Then the program exits with code 3 within 10000 milliseconds
    And stdout includes:
      """
      "code":"UNAVAILABLE"
      """

  Scenario: Whoami returns JSON on authentication failure
    Given the test server is running
    When I run whoami as JSON with key "wrong"
    Then whoami exits with code 3
    And whoami output contains "UNAUTHORIZED"

  Scenario: A server error is not an authentication error
    Given a server with broken authentication is running
    When I run whoami as JSON with key "wrong"
    Then whoami exits with code 3
    And whoami output contains "UNAVAILABLE"

  Scenario: Whoami retries a transient connection failure
    Given a transient server is running
    When I run whoami with key "01234567890123456789012345678901"
    Then whoami exits with code 0

  Scenario: Whoami retries a busy server
    Given a server is busy "0"
    When I run whoami with key "01234567890123456789012345678901"
    Then whoami exits with code 0

  Scenario: Whoami reports a server that remains busy
    Given a server is busy "1"
    When I run whoami as JSON with key "01234567890123456789012345678901"
    Then whoami exits with code 3
    And whoami output contains "BUSY"

  Scenario: Usage errors are JSON when requested
    Given the program argument "whoami"
    And the program argument "--json"
    And the program argument "--bad"
    And the Agentica program "../cli.agc"
    Then the program exits with code 2 within 10000 milliseconds
    And stdout includes:
      """
      "code":"INVALID"
      """

  Scenario: Whoami rejects an invalid authentication response
    Given a server with an invalid authentication response is running
    When I run whoami as JSON with key "wrong"
    Then whoami exits with code 3
    And whoami output contains "UNAVAILABLE"

  Scenario Outline: Invalid configuration is reported
    Given the home fixture is "<fixture>"
    And the program argument "whoami"
    And the program argument "--json"
    And the Agentica program "../cli.agc"
    Then the program exits with code 2 within 10000 milliseconds
    And stdout includes:
      """
      "code":"INVALID"
      """

    Examples:
      | fixture  |
      | bad_toml |
      | bad_type |
