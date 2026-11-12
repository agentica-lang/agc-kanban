Feature: CLI boards
  Scenario: List the boards
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "board list"
    Then kanban exits with code 0
    And kanban output contains "project"

  Scenario: List the boards as JSON
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I run kanban "board list --json"
    Then kanban exits with code 0
    And kanban output contains "\"slug\":\"project\""

  Scenario: Create a board from the CLI
    Given the database server is running
    When I run kanban "board create Project --slug project"
    Then kanban exits with code 0
    And kanban output contains "project"
    When I list boards
    Then the response contains "Project"

  Scenario: Show a board and its cards
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I run kanban "board show project"
    Then kanban exits with code 0
    And kanban output contains "First"
    And kanban output contains "Todo"

  Scenario: An unknown board command is a usage error
    Given the database server is running
    When I run kanban "board nope"
    Then kanban exits with code 2
    And kanban output contains "USAGE"
