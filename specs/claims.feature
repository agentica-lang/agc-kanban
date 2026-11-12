Feature: Card claims
  Scenario: A card can be claimed by only one agent
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Implement API"
    Then the response status is 201
    When agent "agent-1" claims card 1
    Then the response status is 200
    And the response contains "\"claimed_by\":\"agent-1\""
    And the response contains "\"column\":\"Doing\""
    When agent "agent-2" claims card 1
    Then the response status is 409
    And the response contains "CLAIMED"
    And the response contains "agent-1"
    When agent "agent-1" claims card 1
    Then the response status is 200

  Scenario: Claiming a missing card is not found
    Given the database server is running
    When agent "agent-1" claims card 999
    Then the response status is 404
    And the response contains "NOT_FOUND"

  Scenario: Eight agents race for the same card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Implement API"
    Then the response status is 201
    When eight agents race to claim card 1
    Then one agent wins and seven receive CLAIMED

  Scenario: Negative lease configuration is rejected
    Given the environment variable "KANBAN_API_KEY" is "01234567890123456789012345678901"
    And the environment variable "KANBAN_LEASE_MINUTES" is "-1"
    And the Agentica program "../server.agc"
    Then the program exits with code 1 within 30000 milliseconds
    And stderr includes:
      """
      invalid KANBAN_LEASE_MINUTES
      """

  Scenario: Eight agents claim eight different ready cards
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add eight cards
    And eight agents race to claim the next card
    Then each agent claims a different card
