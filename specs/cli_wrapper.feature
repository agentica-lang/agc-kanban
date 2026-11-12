Feature: CLI wrapper
  Scenario: A reader that has left ends the CLI quietly
    When I run the kanban wrapper whose reader has left "prime"
    Then kanban exits with code 141
    And kanban stdout is empty
    And kanban stderr is empty

  Scenario: The wrapper hands piped standard input to the CLI
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    Then the response status is 201
    When I add a card titled "First"
    Then the response status is 201
    When I run the kanban wrapper "card comment 1 -" reading the body "a note through the wrapper"
    Then kanban exits with code 0
    When I run kanban "card show 1"
    Then kanban output contains "a note through the wrapper"

  Scenario: QUIT stops the CLI with the wrapper
    When I send QUIT to the kanban wrapper while it waits
    Then kanban exits with code 131
    And kanban stdout contains "child gone"
    And kanban stdout contains "temp gone"
