Feature: CLI columns
  Scenario: Add a column
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "column add Testing --board project --position 3"
    Then kanban exits with code 0
    And kanban output contains "Testing"
    When I get the project snapshot
    Then the response contains "Testing"

  Scenario: Rename and move a column
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "column rename Todo Backlog --board project"
    Then kanban exits with code 0
    And kanban output contains "Backlog"
    When I run kanban "column move Backlog 2 --board project"
    Then kanban exits with code 0
    And kanban output contains "moved"
    When I get the project snapshot
    Then the response contains "Backlog"

  Scenario: Remove an empty column
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add the column "Testing" at position 3
    Then the response status is 201
    When I run kanban "column remove Testing --board project"
    Then kanban exits with code 0
    And kanban output contains "removed"
    When I get the project snapshot
    Then the response does not contain "Testing"

  Scenario: A column with cards cannot be removed
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I run kanban "column remove Todo --board project"
    Then kanban exits with code 1
    And kanban output contains "CONFLICT"

  Scenario: A missing board is a usage error
    Given the database server is running
    When I run kanban "column add Testing"
    Then kanban exits with code 2
    And kanban output contains "INVALID"

  Scenario: An unknown column is not found
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "column rename Nope Other --board project"
    Then kanban exits with code 1
    And kanban output contains "NOT_FOUND"
