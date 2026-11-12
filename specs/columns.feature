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

  Scenario: Rename a column and record the event
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I rename column 2 to "In progress"
    Then the response status is 200
    And the response contains "In progress"
    When I get board events for "project" after 1
    Then the response contains "column.updated"
    And the response contains "In progress"

  Scenario: Delete an empty column and record the event
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I delete column 2
    Then the response status is 204
    When I get board events for "project" after 1
    Then the response contains "column.removed"

  Scenario: A column with cards cannot be deleted
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First card"
    Then the response status is 201
    When I delete column 1
    Then the response status is 409
    And the response contains "CONFLICT"
    When I get board events for "project" after 2
    Then the response contains "\"events\":[]"

  Scenario: Only one column is the done column
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I mark column 2 as done
    Then the response status is 200
    And the response contains "\"done\":true"
    When I mark column 4 as done
    Then the response status is 200
    When I get the project snapshot
    Then the response status is 200
    And the response contains exactly 1 occurrences of "\"done\":true"
    When I get board events for "project" after 1
    Then the response contains "column.updated"
