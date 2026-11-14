Feature: CLI labels
  Scenario: List the labels with their colors
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First" with labels "api,ui" and priority 2
    And I run kanban "label list --board project"
    Then kanban exits with code 0
    And kanban output contains "api"
    And kanban output contains "#"
    When I run kanban "label list --board project --json"
    Then kanban output contains "\"color\""

  Scenario: Change a color and a name
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First" with labels "api" and priority 2
    And I run kanban "label update api --color #00ff7f --board project"
    Then kanban exits with code 0
    And kanban output contains "updated"
    And kanban output contains "#00ff7f"
    When I run kanban "label update api --name backend --board project"
    Then kanban exits with code 0
    When I run kanban "card list --board project"
    Then kanban output contains "[backend]"
    And kanban output does not contain "#00ff7f"

  Scenario: A bad color, an unknown label and a missing change are refused
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "First" with labels "api" and priority 2
    And I run kanban "label update api --color red --board project"
    Then kanban exits with code 1
    And kanban output contains "INVALID"
    When I run kanban "label update nope --color #00ff7f --board project"
    Then kanban exits with code 1
    And kanban output contains "NOT_FOUND"
    When I run kanban "label update api --board project"
    Then kanban exits with code 2
    And kanban output contains "USAGE"

  Scenario: A label update needs an agent name
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I run kanban without an agent "label update api --color #00ff7f --board project"
    Then kanban exits with code 2
    And kanban output contains "USAGE"
