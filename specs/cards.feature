Feature: Cards
  Scenario: Create and read a card
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "Implement API"
    Then the response status is 201
    And the response contains "Implement API"
    And the response contains "\"ready\":true"
    When I get card 1
    Then the response status is 200
    And the response contains "Implement API"
    And the response contains "\"comments\":[]"

  Scenario: Missing card returns not found
    Given the database server is running
    When I get card 999
    Then the response status is 404
    And the response contains "NOT_FOUND"
