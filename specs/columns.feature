Feature: Board columns
  Scenario: Add a column at a position
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add the column "Testing" at position 1
    Then the response status is 201
    And the response contains "Testing"
    And the response contains "\"position\":1"
    When I get board events for "project" after 0
    Then the response contains "column.added"

  Scenario: Reject a duplicate column without recording an event
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add the column "Todo" at position 1
    Then the response status is 409
    And the response contains "CONFLICT"
    When I get board events for "project" after 1
    Then the response contains "\"events\":[]"
