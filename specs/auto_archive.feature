Feature: Automatic archive of the done cards
  Scenario: A board turns the automatic archive on and off, and it is off by default
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I run kanban "board show project"
    Then kanban output does not contain "auto-archive"
    When I run kanban "board auto-archive --board project --days 3"
    Then kanban exits with code 0
    And kanban output contains "auto-archive"
    And kanban output contains "3 days"
    When I run kanban "board show project"
    Then kanban output contains "auto-archive: 3 days"
    When I get board events for "project" after 0
    Then the response contains "\"kind\":\"board.updated\""
    And the response contains "\"auto_archive_days\":3"
    When I run kanban "board auto-archive --board project --off"
    Then kanban output contains "off"
    When I run kanban "board show project"
    Then kanban output does not contain "auto-archive"

  Scenario: Bad requests and the web session change nothing
    Given the database server is running
    When I post a board named "Project" with slug "project" as "agent-1"
    And I run kanban "board auto-archive --board project --days 0"
    Then kanban exits with code 1
    And kanban stderr contains "INVALID"
    When I run kanban "board auto-archive --board project"
    Then kanban exits with code 2
    When I run kanban "board auto-archive --board project --days 3 --off"
    Then kanban exits with code 2
    When I run kanban "board auto-archive --board nowhere --days 3"
    Then kanban exits with code 1
    And kanban stderr contains "NOT_FOUND"
    When I run kanban without an agent "board auto-archive --board project --days 3"
    Then kanban exits with code 2
    When I sign in with the key "01234567890123456789012345678901"
    And I post "/api/boards/project/auto-archive" with the session as agent "web" and the body "{\"days\":3}"
    Then the response status is 401
    When I get board events for "project" after 0
    Then the response does not contain "board.updated"
