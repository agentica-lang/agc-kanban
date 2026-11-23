Feature: CLI milestones
  Scenario: Create, list, update, close, reopen and remove a milestone
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I add a card titled "A" with labels "0.37.0" and priority 2
    And I add a card titled "B" with labels "0.37.0" and priority 2
    And I run kanban "milestone create 0.37.0 --description Big --due 2099-12-01 --board project"
    Then kanban exits with code 0
    And kanban output contains "created"
    And kanban output contains "0.37.0"
    When I move card 1 to "Done"
    And I run kanban "milestone list --board project"
    Then kanban exits with code 0
    And kanban output contains "0.37.0"
    And kanban output contains "50%"
    And kanban output contains "1 open"
    And kanban output contains "1 closed"
    And kanban output contains "2099-12-01"
    When I run kanban "milestone list --board project --json"
    Then kanban output contains "\"percent\":50"
    When I run kanban "milestone update 0.37.0 --description Json --board project --json"
    Then kanban exits with code 0
    And kanban output contains "\"milestone\""
    And kanban output contains "\"description\":\"Json\""
    When I run kanban "milestone update 0.37.0 --no-due --board project"
    Then kanban exits with code 0
    And kanban output contains "50%"
    And kanban output does not contain "2099-12-01"
    When I run kanban "milestone update 0.37.0 --description Later --due 2099-06-01 --board project"
    Then kanban output contains "2099-06-01"
    When I run kanban "milestone close 0.37.0 --board project"
    Then kanban exits with code 0
    And kanban output contains "closed"
    When I run kanban "milestone list --board project"
    Then kanban output does not contain "0.37.0"
    When I run kanban "milestone list --state closed --board project"
    Then kanban output contains "0.37.0"
    When I run kanban "milestone reopen 0.37.0 --board project"
    Then kanban output contains "reopened"
    When I run kanban "milestone remove 0.37.0 --board project"
    Then kanban exits with code 0
    And kanban output contains "removed"
    When I run kanban "milestone list --state all --board project"
    Then kanban output does not contain "0.37.0"
    When I run kanban "card list --board project"
    Then kanban output contains "[0.37.0]"

  Scenario: A bad date, an unknown milestone and a missing change are refused
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I run kanban "milestone create x --due 2026-02-30 --board project"
    Then kanban exits with code 1
    And kanban output contains "INVALID"
    When I run kanban "milestone create x --board project"
    Then kanban exits with code 0
    When I run kanban "milestone create x --board project"
    Then kanban exits with code 1
    And kanban output contains "CONFLICT"
    When I run kanban "milestone update x --due 2026-02-30 --board project"
    Then kanban exits with code 1
    And kanban output contains "INVALID"
    When I run kanban "milestone"
    Then kanban exits with code 2
    When I run kanban "milestone nope"
    Then kanban exits with code 2
    When I run kanban "milestone list"
    Then kanban exits with code 2
    And kanban output contains "USAGE"
    When I run kanban "milestone close nope --board project"
    Then kanban exits with code 1
    And kanban output contains "NOT_FOUND"
    When I run kanban "milestone update x --board project"
    Then kanban exits with code 2
    And kanban output contains "USAGE"
    When I run kanban "milestone update x --due 2099-01-01 --no-due --board project"
    Then kanban exits with code 2
    When I run kanban "milestone list --state half --board project"
    Then kanban exits with code 1
    And kanban output contains "INVALID"

  Scenario: A write needs an agent name and a read does not
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I run kanban without an agent "milestone create x --board project"
    Then kanban exits with code 2
    And kanban output contains "USAGE"
    When I run kanban without an agent "milestone list --board project"
    Then kanban exits with code 0
